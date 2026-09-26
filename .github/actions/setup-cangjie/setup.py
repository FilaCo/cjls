"""Installs a Cangjie nightly SDK and its stdx, and exports the SDK's environment.

    python3 setup.py <tag> <dest>

The SDK is unpacked to <dest>/cangjie, the stdx for the host into
<dest>/cangjie/third_party/stdx/<os>_<arch>_cjnative, where the root cjpm.toml looks for it.
Both are skipped when already there (a cache hit). The environment `envsetup` would set is
written to $GITHUB_ENV/$GITHUB_PATH on GitHub Actions, and printed as `export` lines otherwise.
"""

import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

RELEASES = "https://gitcode.com/Cangjie/nightly_build/releases/download"

# host -> (asset platform, SDK archive extension, stdx directory)
PLATFORMS = {
    ("Darwin", "arm64"): ("mac-aarch64", "tar.gz", "darwin_aarch64_cjnative"),
    ("Linux", "x86_64"): ("linux-x64", "tar.gz", "linux_x86_64_cjnative"),
    ("Windows", "AMD64"): ("windows-x64", "zip", "windows_x86_64_cjnative"),
}

# changed by any shell, not by envsetup
SHELL_NOISE = {"_", "SHLVL", "PWD", "OLDPWD"}


def download(url, path):
    print(f"downloading {url}", file=sys.stderr)
    request = urllib.request.Request(url, headers={"User-Agent": "cjls-ci"})
    with urllib.request.urlopen(request) as response, open(path, "wb") as out:
        shutil.copyfileobj(response, out, 1 << 20)


def unpack(archive, dest):
    if archive.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            z.extractall(dest)
    else:
        with tarfile.open(archive) as t:
            # keeps the SDK's symlinks and modes; the archive is the toolchain's own
            if hasattr(tarfile, "tar_filter"):
                t.extractall(dest, filter="tar")
            else:
                t.extractall(dest)


def install(tag, dest):
    asset, ext, stdx_dir = PLATFORMS[(platform.system(), platform.machine())]
    home = os.path.join(dest, "cangjie")
    os.makedirs(dest, exist_ok=True)
    if not os.path.isdir(os.path.join(home, "bin")):
        archive = os.path.join(dest, f"sdk.{ext}")
        download(f"{RELEASES}/{tag}/cangjie-sdk-{asset}-{tag}.{ext}", archive)
        unpack(archive, dest)
        os.remove(archive)
    stdx_root = os.path.join(home, "third_party", "stdx")
    if not os.path.isdir(os.path.join(stdx_root, stdx_dir, "static", "stdx")):
        archive = os.path.join(dest, "stdx.zip")
        download(f"{RELEASES}/{tag}/cangjie-stdx-{asset}-{tag}.1.zip", archive)
        unpack(archive, stdx_root)
        os.remove(archive)
    return home


def environment(home):
    """What envsetup changes: (variables, PATH entries to prepend in order)."""
    before = dict(os.environ)
    if platform.system() == "Windows":
        # envsetup.ps1, spelled out: it only sets CANGJIE_HOME and prepends to Path
        after = dict(before)
        after["CANGJIE_HOME"] = home
        entries = [
            os.path.join(home, "tools", "lib"),
            os.path.join(home, "tools", "bin"),
            os.path.join(home, "bin"),
            os.path.join(home, "lib", "windows_x86_64_cjnative"),
            os.path.join(home, "runtime", "lib", "windows_x86_64_cjnative"),
        ]
        after["PATH"] = os.pathsep.join(entries + [before.get("PATH", "")])
    else:
        script = 'source "$1" >/dev/null && "$2" -c "import json, os; print(json.dumps(dict(os.environ)))"'
        out = subprocess.run(
            ["bash", "-c", script, "_", os.path.join(home, "envsetup.sh"), sys.executable],
            check=True, capture_output=True, text=True,
        ).stdout
        after = json.loads(out.strip().splitlines()[-1])
    old_path = before.get("PATH", "").split(os.pathsep)
    path = [p for p in after.get("PATH", "").split(os.pathsep) if p and p not in old_path]
    changed = {
        k: v for k, v in after.items()
        if k != "PATH" and k not in SHELL_NOISE and before.get(k) != v
    }
    return changed, path


def main():
    tag, dest = sys.argv[1], os.path.abspath(sys.argv[2])
    home = install(tag, dest)
    variables, path = environment(home)
    github_env, github_path = os.environ.get("GITHUB_ENV"), os.environ.get("GITHUB_PATH")
    if github_env and github_path:
        with open(github_env, "a") as f:
            for k, v in variables.items():
                f.write(f"{k}={v}\n")
        # each line is prepended, so the first entry goes last
        with open(github_path, "a") as f:
            for p in reversed(path):
                f.write(p + "\n")
    else:
        for k, v in variables.items():
            print(f"export {k}='{v}'")
        print(f"export PATH='{os.pathsep.join(path)}'{os.pathsep}\"$PATH\"")


if __name__ == "__main__":
    main()
