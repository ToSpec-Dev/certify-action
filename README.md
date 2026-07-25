# ToSpec-Dev/certify-action

Certify your API integration against a [ToSpec](https://tospec.dev) suite on every
push. This Action wraps the [`tospec` CLI](https://github.com/ToSpec-Dev/cli): it starts a
certification session, waits for the verdict, **fails the build when the integration
doesn't conform**, and posts the remediation report — the exact changes to make — to
the job summary.

## Quick start

```yaml
name: certify
on: [push]

jobs:
  conformance:
    runs-on: ubuntu-latest
    steps:
      - uses: ToSpec-Dev/certify-action@v1.0.0
        with:
          suite: channelrush-pms
          pat: ${{ secrets.TOSPEC_PAT }}
          cli-version: v1.2.0
```

Store a partner access token (with the `sessions:write` and `sessions:read` scopes) as
the `TOSPEC_PAT` repository secret. Create it in the ToSpec partner portal under
**Settings → Access tokens**.

When the run fails, the step fails and the job summary shows the remediation report:

> ## ToSpec certification: fail
> ```markdown
> # Remediation report — session 0c3e…
> ## Changes to make
> 1. simple-rate-update / rate-update — blocking · 15 pts at stake
>    - Failed assertion: `$.successful` expected `true`, observed `false` …
> ```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `suite` | yes | — | Suite slug (its latest published version is used) |
| `pat` | yes | — | Partner token with `sessions:write` + `sessions:read` (pass a secret) |
| `url` | no | `https://api.tospec.dev` | Portal API base URL |
| `wait` | no | `true` | Wait for the graded verdict |
| `capabilities` | no | — | Declared integration modes, one `name=value` per line |
| `timeout` | no | `900` | Max seconds to wait for a verdict |
| `poll-interval` | no | `5` | Status poll cadence (seconds) |
| `cli-version` | yes | — | Immutable `ToSpec-Dev/cli` release tag; its published SHA-256 is verified before execution |
| `traffic-command` | no | — | Command to run after opening the session and before waiting for its verdict |
| `fail-on` | no | `fail` | `fail` (fail on failure or error), `error` (only on error), or `never` |

## Outputs

| Output | Description |
|---|---|
| `result` | `pass`, `fail`, or `error` |
| `exit-code` | The CLI exit code: `0` pass, `1` fail, `2` error |

## Declaring capabilities

Some suites require you to declare an integration mode. Pass them one per line:

```yaml
- uses: ToSpec-Dev/certify-action@v1.0.0
  with:
    suite: channelrush-pms
    pat: ${{ secrets.TOSPEC_PAT }}
    cli-version: v1.2.0
    capabilities: |
      auth_style=oauth2
      rate_format=nested
```

## Report without blocking

To surface conformance drift without failing the build (e.g. on a `main` dashboard job):

```yaml
- uses: ToSpec-Dev/certify-action@v1.0.0
  with:
    suite: channelrush-pms
    pat: ${{ secrets.TOSPEC_PAT }}
    cli-version: v1.2.0
    fail-on: error   # a certification failure is reported, only a hard error blocks
```

## How it works

The Action downloads the self-contained `tospec` binary and matching checksum for the
runner's OS/arch from the pinned `ToSpec-Dev/cli` release, verifies it before execution
(no .NET required on the runner), runs `tospec run --wait`, and on a non-pass runs `tospec remediation` into the job summary. The CLI's
exit code becomes the step's outcome. There is no logic here the CLI doesn't already
own — this is packaging.

When `traffic-command` is supplied, the Action opens the session without waiting,
runs that command, then re-enters the same idempotency-keyed session and waits. This
lets a sample or test integration generate real traffic inside the certification
window rather than merely opening an idle session.

## License

Apache-2.0.
