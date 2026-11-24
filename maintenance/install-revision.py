import io
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def git(repository, *args):
    return subprocess.check_output(["git", *args], cwd=repository)


def install_revision(repository, state):
    revision = git(repository, "rev-parse", "HEAD").decode().strip()
    if (
        git(repository, "branch", "--show-current").strip() != b"main"
        or git(repository, "rev-parse", "refs/remotes/origin/main").strip() != revision.encode()
        or git(repository, "status", "--porcelain", "--untracked-files=all")
    ):
        raise SystemExit("Run workspace setup from a clean main checkout fast-forwarded to origin/main.")
    if state.is_relative_to(repository):
        raise SystemExit("Keep maintenance state outside the public checkout.")

    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    state.chmod(0o700)
    releases = state / "revisions"
    releases.mkdir(mode=0o700, exist_ok=True)
    destination = releases / revision
    if destination.is_dir():
        return f"Current {revision}"

    with tempfile.TemporaryDirectory(dir=releases) as directory:
        extracted = Path(directory) / revision
        extracted.mkdir(mode=0o700)
        contents = io.BytesIO(git(repository, "archive", "--format=tar", revision))
        with tarfile.open(fileobj=contents) as archive:
            archive.extractall(extracted, filter="data")
        extracted.rename(destination)
    return f"Installed {revision}"


if __name__ == "__main__":
    print(install_revision(Path(__file__).resolve().parents[1], Path(sys.argv[1]).resolve()))
