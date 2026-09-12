import os
import pathlib
import tempfile

_tmp = tempfile.mkdtemp(prefix="mealee-test-")
os.environ["SQLITE_PATH"] = str(pathlib.Path(_tmp) / "test.sqlite")
os.environ["UPLOAD_DIR"] = str(pathlib.Path(_tmp) / "uploads")
os.environ["REDIS_URL"] = ""
os.environ["MONGODB_URI"] = ""
os.environ["IFM_API_KEY"] = ""
