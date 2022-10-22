import os, sys

exe_name = "mani"
root_dir = os.path.join("../", os.path.realpath(__file__))
odin_command = "odin"

odin_options = {
    "show-timings": True,
    "debug": True,
    "ignore-unknown-attribs": True
}

odin_collections = {
    "foreign": "foreign"
}


if sys.platform == "win32":
    exe_extension = ".exe"
else:
    exe_extension = ""