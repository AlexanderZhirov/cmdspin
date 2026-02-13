# cmdspin

Small D library for running external commands with a terminal spinner.

Two execution styles:
- **CmdSpinExecute** — run a command and handle `(status, output)` (captured output).
- **CmdSpinPipes** — run a command and handle `(stdout, stderr)` as streams.

## Install (dub)

```json
{
	"dependencies": {
		"cmdspin": "~>0.1.1"
	}
}
```

## Usage

See the [example](example/) directory.

## License

Boost Software License 1.0. See [LICENSE](LICENSE).
