# Setup

## User Guide

`gradescopeapi` is available on [PyPi](https://pypi.org/project/gradescopeapi/) and can be installed using your favorite Python package manager.

For example, `pip install gradescopeapi` or `uv add gradescopeapi`

## Development Guide

Clone/Fork the repository. This project currently uses [uv](https://docs.astral.sh/uv/) for project management.

[Just](https://github.com/casey/just) is also used as a command runner to simplify repeated commands.

### Development Steps

1. Install [uv](https://docs.astral.sh/uv/#getting-started)
1. Navigate to project root `cd gradescopeapi`
1. Create a virtual environment `uv venv`
1. Activate virtual environment
   - (macOS/Linux) `source .venv/bin/activate`
   - (Windows) `.venv\Scripts\activate`
1. Update the project's environment `uv sync --all-extras`
1. Run `just` to see all available command targets.
   - Just is added as a development dependency and should not need separate installation
