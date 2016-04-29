from distutils.core import setup, Extension

core = Extension('pysproto.core',
        sources = ["pysproto/python_sproto.c", "pysproto/sproto.c"],
        )

setup(
        name = "pysproto",
        version = '0.1',
        packages = ["pysproto"],
        description = "python binding for cloudwu's sproto",
        author = "bttscut",
        license = "MIT",
        url="http://github.com/bttscut/pysproto",
        keywords=["sproto", "python"],
        # py_modules = ["sproto.py"],
        ext_modules = [core]
        )
