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
            f.write(f"\n\n{stamp} Importing {arch} from {url}\n")

            while True:
                if await request.is_disconnected():
                    pass  # continue process and writing log file

                output = process.stdout.readline()
                if output:
                    f.write(output)
                    yield output[:-1]

                elif process.poll() is not None:
                    break  # process finished

                await asyncio.sleep(1)

            if process.returncode != 0:
                output = f"Failed with return code {process.returncode}\n"
                f.write(output)
                yield output[:-1]

        yield ""  # signal end of stream
        global running
        running = None

    return EventSourceResponse(processor())
