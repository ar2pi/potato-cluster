import asyncio
import logging
import time
from typing import Callable

from fastapi import FastAPI, HTTPException, Request

# Disable Uvicorn's default logger
logging.getLogger("uvicorn.access").disabled = True

logging.basicConfig(
    level=logging.DEBUG, format="%(asctime)s %(levelname)s: %(message)s"
)
logger = logging.getLogger(__name__)

app = FastAPI()
mem_leak: list = []


@app.middleware("http")
async def log_requests(request: Request, call_next: Callable):
    # @TODO: log request duration
    response = None
    log_line = f'{request.client.host}:{request.client.port} - "{request.method} {request.url.path}'
    if request.query_params:
        log_line += f"?{request.query_params}"
    log_line += f' {request.headers.get("server_protocol", "HTTP/1.1")}"'
    try:
        response = await call_next(request)
        log_line += f" {response.status_code} OK"
        if 500 > response.status_code > 400:
            logger.warning(log_line)
        elif response.status_code >= 500:
            logger.error(log_line)
        else:
            logger.info(log_line)
        return response
    except Exception as e:
        log_line += f" 500 NOT OK"
        logger.error(log_line, exc_info=True)
        raise e


# @app.exception_handler(HTTPException)
# async def http_exception_handler(request: Request, exc: HTTPException):
#     logger.error(
#         f'{request.client.host}:{request.client.port} - "{request.method} {request.url.path}?{request.query_params} {request.headers.get("server_protocol", "HTTP/1.1")}" {exc.status_code}'
#     )
#     return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.get("/hello")
async def hello(name: str = "world"):
    logger.debug(f"Hello, {name}!")
    return {"message": f"Hello, {name}!"}


@app.get("/fail")
async def fail(
    status_code: int = 500, force_success: bool = False, with_mem_leak: bool = False
):
    if with_mem_leak:
        mem_leak.append(bytearray(4 * 1024))
    if force_success:
        logger.info("ok")
        return {"message": "ok"}
    logger.error(f"Woops, something went wrong")
    raise HTTPException(status_code=status_code, detail="Woops")


@app.get("/wait")
async def wait(time_ms: int = 10000):
    await asyncio.sleep(time_ms / 1000)
    logger.warning(f"Waited {time_ms}ms")
    return {"message": f"Waited {time_ms/1000}s"}


@app.get("/health")
async def health():
    return "ok"
