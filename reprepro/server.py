# fastapi run server.py

from sse_starlette.sse import EventSourceResponse
from fastapi import FastAPI, Request, Response
import asyncio
import os
import subprocess
import time
from pathlib import Path
import logging

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# get Path to current working directory
if not (Path(os.getcwd()) / "conf" / "distributions").is_file():
    print("Need to run from the reprepro root directory")
    exit(1)

# https://www.google.com/search?q=fastapi+provide+response+from+long-running+call&oq=fastapi+provide+response+from+long-running+call&gs_lcrp=EgZjaHJvbWUyBggAEEUYOTIHCAEQIRigATIHCAIQIRigATIHCAMQIRiPAjIHCAQQIRiPAtIBCTE0MjM4ajBqNKgCALACAQ&sourceid=chrome&ie=UTF-8
# https://blog.stackademic.com/managing-long-running-processes-with-fastapi-in-python-a5de07eaf76a
# https://sairamkrish.medium.com/handling-server-send-events-with-python-fastapi-e578f3929af1
# https://medium.com/@Rachita_B/lookout-for-these-cryptids-while-working-with-server-sent-events-43afabb3a868

running = None
app = FastAPI()


@app.get("/import")
def reprepro_import(request: Request, run_id: str = "", arch: str = "x64"):
    global running
    if running:
        return Response(
            content=f"Blocked by active import from: {running}",
            media_type="text/plain",
            status_code=503,
        )

    env = os.environ.copy()
    env["ARCH"] = arch
    env["RUN_ID"] = run_id
    env["REPO"] = repo = f"ubi_agni/ros-builder-action"

    running = f"https://github.com/{repo}/actions/runs/{run_id}"

    import_script = Path(__file__).parent / "import.sh"
    process = subprocess.Popen(
        [import_script.as_posix()],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )

    async def processor():
        with open("import.log", "a", encoding="utf-8") as f:
            stamp = time.strftime("%Y-%m-%d %H:%M:%S")
            url = f"https://github.com/{repo}/actions/runs/{run_id}"
            f.write(f"\n\n{stamp}\nImporting {arch} from {url}\n")

            try:
                while True:
                    output = process.stdout.readline()
                    if output:
                        f.write(output)
                        yield output[:-1]

                    elif process.poll() is not None:  # process finished
                        if process.returncode != 0:
                            output = f"Failed with return code {process.returncode}\n"
                            yield output[:-1]
                        yield ""  # signal end of stream
                        break

            except asyncio.CancelledError:  # client disconnected
                # continue process and writing log
                while True:
                    output = process.stdout.readline()
                    if output:
                        f.write(output)
                    elif process.poll() is not None:
                        if process.returncode != 0:
                            output = f"Failed with return code {process.returncode}\n"
                        break  # process finished

            f.write(output)

        global running
        running = None

    return EventSourceResponse(processor())
