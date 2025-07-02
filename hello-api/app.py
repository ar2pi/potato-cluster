import asyncio
import logging
import os
from typing import Callable

from fastapi import FastAPI, HTTPException, Request

# Metrics
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.instrumentation.system_metrics import SystemMetricsInstrumentor
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter

# Logs
from opentelemetry._logs import set_logger_provider
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter

# Traces
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# Profiles
import pyroscope
from pyroscope.otel import PyroscopeSpanProcessor

# Flask instrumentation
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

OTEL_EXPORTER_OTLP_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317"
)
PYROSCOPE_SERVER_ADDRESS = os.getenv(
    "PYROSCOPE_SERVER_ADDRESS", "http://localhost:4040"
)

# Disable Uvicorn's default logger
logging.getLogger("uvicorn.access").disabled = True
# Configure logger
logging.basicConfig(
    level=logging.DEBUG, format="%(asctime)s %(levelname)s: %(message)s"
)
logger = logging.getLogger(__name__)

# Set up metrics
metric_reader = PeriodicExportingMetricReader(
    # https://opentelemetry-python.readthedocs.io/en/latest/exporter/otlp/otlp.html#opentelemetry.exporter.otlp.proto.grpc.metric_exporter.OTLPMetricExporter
    OTLPMetricExporter(endpoint=OTEL_EXPORTER_OTLP_ENDPOINT)
)
meter_provider = MeterProvider(metric_readers=[metric_reader])
metrics.set_meter_provider(meter_provider)

# Set up logs
logger_provider = LoggerProvider()
set_logger_provider(logger_provider)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(
        # https://opentelemetry-python.readthedocs.io/en/latest/exporter/otlp/otlp.html#opentelemetry.exporter.otlp.proto.grpc._log_exporter.OTLPLogExporter
        OTLPLogExporter(endpoint=OTEL_EXPORTER_OTLP_ENDPOINT)
    )
)
logging_handler = LoggingHandler(level=logging.NOTSET, logger_provider=logger_provider)
logging.getLogger().addHandler(logging_handler)

# Set up traces
tracer_provider = TracerProvider()
span_processor = BatchSpanProcessor(
    # https://opentelemetry-python.readthedocs.io/en/latest/exporter/otlp/otlp.html#opentelemetry.exporter.otlp.proto.grpc.trace_exporter.OTLPSpanExporter
    OTLPSpanExporter(endpoint=OTEL_EXPORTER_OTLP_ENDPOINT)
)
tracer_provider.add_span_processor(span_processor)
# Link traces to pyroscope
# https://grafana.com/docs/pyroscope/latest/configure-client/trace-span-profiles/python-span-profiles/
tracer_provider.add_span_processor(PyroscopeSpanProcessor())
trace.set_tracer_provider(tracer_provider)

# Set up profiles
pyroscope.configure(
    application_name="hello-api",
    server_address=PYROSCOPE_SERVER_ADDRESS,
    enable_logging=True,  # debug pyroscope logs
)

app = FastAPI()
mem_leak: list = []

# https://opentelemetry-python-contrib.readthedocs.io/en/latest/instrumentation/fastapi/fastapi.html
FastAPIInstrumentor.instrument_app(
    app,
    tracer_provider=tracer_provider,
    meter_provider=meter_provider,
)
# https://opentelemetry-python-contrib.readthedocs.io/en/latest/instrumentation/logging/logging.html
LoggingInstrumentor().instrument(
    tracer_provider=tracer_provider,
    set_logging_format=True,
    log_level=logging.DEBUG,
)
# https://opentelemetry-python-contrib.readthedocs.io/en/latest/instrumentation/system_metrics/system_metrics.html
SystemMetricsInstrumentor().instrument()


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
