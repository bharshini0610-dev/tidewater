import os

# prometheus_client picks single- or multi-process mode when it is first imported, and
# treats the variable as set even when it is empty (the worker sets it to ""). Decide here,
# before any settle module imports prometheus_client.
if not os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
    os.environ.pop("PROMETHEUS_MULTIPROC_DIR", None)
