# fastapi run server.py

from sse_starlette.sse import EventSourceResponse
from fastapi import FastAPI, Request, Response
import asyncio
from enum import Enum
import os
import queue
import subprocess
import time
from threading import Thread
from pathlib import Path
import logging

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# get Path to current working directory
if not (Path(os.getcwd()) / "conf" / "distributions").is_file():
    print("Need to run from the reprepro root directory")
    exit(1)

running = None
app = FastAPI()


class Status(Enum):
    STARTED = 1
    DOWNLOADING = 2
    IMPORTING = 3


def process(q: queue.Queue, distro: str, repo: str, arch: str, run_id: str):
    """Process import request, writing http response to queue"""
    global running
    url = f"https://github.com/{repo}/actions/runs/{run_id}"
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")

    while running:
        q.put(f"Blocked by active import from: {running}")
        time.sleep(2)

    if q.cancelled:  # skip processing if client already disconnected
        print(f"Cancelling import from {url}")
        return

    running = f"{url} started at {stamp}"

    home = os.environ["HOME"]
    log = open(f"{home}/import.log", "a", encoding="utf-8")
    log.write(f"\n\n{stamp}\nImporting {arch} from {url}\n")
    q.put(f"Importing {arch} from {url}")

    # Run import script
    env = os.environ.copy()
    env.update(DISTRO=distro, ARCH=arch, RUN_ID=run_id, REPO=repo)
    import_script = Path(__file__).parent / "import.sh"
    p = subprocess.Popen(
        [import_script.as_posix()],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )

    while True:
        if output := p.stdout.readline():
            log.write(output)
            q.put(output[:-1] or " ")  # strip newline and ensure non-empty string
        elif p.poll() is not None:  # process finished
            if p.returncode != 0:
                q.put(f"Failed with return code {p.returncode}")
            break

    q.put("")  # empty string signals end of stream
    running = None


@app.get("/import")
def reprepro_import(request: Request, distro: str, run_id: str, arch: str = "x64"):
    kwargs = dict(
        repo="ubi-agni/ros-builder-action", distro=distro, run_id=run_id, arch=arch
    )
    q = queue.Queue()
    q.cancelled = False
    t = Thread(target=process, args=(q,), kwargs=kwargs, daemon=True)
    t.start()

    async def processor():
        status = Status.STARTED
        size_cmd = "ls -1st /tmp/gh*.zip 2> /dev/null | head -n 1 | cut -d ' ' -f1"
        size = -1
        try:
            while True:
                try:
                    response = q.get_nowait()
                    if status == Status.STARTED and response.startswith("Fetching "):
                        status = Status.DOWNLOADING
                    elif status == Status.DOWNLOADING or status == Status.IMPORTING:
                        status = Status.IMPORTING
                        size = 0

                    yield response
                    if not response:
                        break
                except queue.Empty:
                    if status == Status.DOWNLOADING:
                        newsize = int(subprocess.getoutput(size_cmd) or 0)
                        if newsize > size:
                            size = newsize
                            yield f"Downloading artifact: {size}"
                        else:
                            yield "Extracting artifact"
                    elif status == Status.IMPORTING:
                        size += 1
                        if size >= 10:
                            yield "Import stalled. Killing unzstd."
                            subprocess.run(["pkill", "unzstd"], check=False)

                    await asyncio.sleep(1)

        except asyncio.CancelledError:  # client disconnected
            q.cancelled = True

    return EventSourceResponse(processor())
