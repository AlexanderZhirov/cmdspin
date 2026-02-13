// Small D library for running external commands with a terminal spinner v0.1.1;
module cmdspin;

import std.process : pipeProcess, ProcessPipes, Redirect, wait, execute, kill, tryWait;
import std.concurrency : Tid, spawn, receiveTimeout, send, thisTid, receive;
import std.stdio : File, writef, write, stdout;
import core.thread : dur;
import std.format : format;
import std.string : fromStringz, startsWith;
import core.sys.posix.signal : SIGTERM;
import core.sys.posix.unistd;

alias posixWrite = core.sys.posix.unistd.write;

private enum string CURSOR_SHOW = "\x1b[?25h\x1b[0m\r\x1b[K";
private enum string CURSOR_HIDE = "\x1b[?25l";

public void cmdspinShowCursor() @nogc nothrow @trusted
{
	posixWrite(STDERR_FILENO, cast(const(void)*) CURSOR_SHOW.ptr, CURSOR_SHOW.length);
}

public void cmdspinHideCursor() @nogc nothrow @trusted
{
	posixWrite(STDERR_FILENO, cast(const(void)*) CURSOR_HIDE.ptr, CURSOR_HIDE.length);
}

private class CmdSpinBase
{
protected:
	Tid _spawnedTid;
	Exception _error;
	int _exitCode;

	struct SpinnerMessage
	{
		bool ln;
		string text;
	}

	struct StopSpinner
	{
		bool stop;
		int exitCode;
	}

	static void spinner(Tid tid, string preMessage, string postMessage, string errorMessage)
	{
		immutable dchar[] animationUTF = [
			'⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'
		];
		immutable dchar[] animationASCII = [
			'-', '\\', '|', '/'
		];

		auto tn = ttyname(0);
		auto ttyName = tn ? tn.fromStringz.idup : string.init;
		auto animation = ttyName.startsWith("/dev/tty") ? animationASCII : animationUTF;

		ulong i = 0;
		string spinnerText = preMessage;

		cmdspinHideCursor();

		bool result = true;
		int resultExitCode;

		while (result)
		{
			writef("\r\x1b[K[%c] %s", animation[i], spinnerText);
			i = (i + 1) % animation.length;

			receiveTimeout(dur!("msecs")(100),
				(SpinnerMessage msg) {
					if (msg.ln)
						writef("\r%s\n", msg.text);
					else
						spinnerText = msg.text;
				},
				(StopSpinner ss) {
					if (ss.stop) {
						resultExitCode = ss.exitCode;
						result = false;
					}
				}
			);

			stdout.flush();
		}

		string endMessage = resultExitCode == 0 ? postMessage : errorMessage;

		cmdspinShowCursor();

		write(endMessage.length ? "[%c] %s\n".format(resultExitCode == 0 ? '#' : '!', endMessage)
				: string.init);

		send(tid, true);
	}

public:
	final @property Exception getError()
	{
		return _error;
	}

	final @property int getExitCode()
	{
		return _exitCode;
	}

	void print(T...)(string fmt, T args)
	{
		send(_spawnedTid, SpinnerMessage(false, fmt.format(args)));
	}

	final void print(string str)
	{
		send(_spawnedTid, SpinnerMessage(false, str));
	}

	void println(T...)(string fmt, T args)
	{
		send(_spawnedTid, SpinnerMessage(true, fmt.format(args)));
	}

	final void println(string str)
	{
		send(_spawnedTid, SpinnerMessage(true, str));
	}
}

class CmdSpinPipes : CmdSpinBase
{
private:
	ProcessPipes pipes;

public:
	final void terminatedProcess()
	{
		if (!pipes.pid.tryWait.terminated)
			pipes.pid.kill(SIGTERM);
	}

	final bool command(
		string[] cmd,
		bool delegate(File pout, File perr) process,
		string startMessage = string.init,
		string stopMessage = string.init,
		string errorMessage = string.init
	)
	{
		_spawnedTid = spawn(&spinner, thisTid, startMessage, stopMessage, errorMessage);

		scope (exit)
		{
			_exitCode = wait(pipes.pid);
			send(_spawnedTid, StopSpinner(true, _exitCode));
			receive((bool done) {});
		}

		try
		{
			pipes = pipeProcess(cmd, Redirect.stdout | Redirect.stderr);
			return process(pipes.stdout, pipes.stderr);
		}
		catch (Exception e)
		{
			_error = e;
			_exitCode = 1;
			return false;
		}
	}
}

class CmdSpinExec : CmdSpinBase
{
	final bool command(
		string[] cmd,
		bool delegate(int status, string output) process,
		string startMessage = string.init,
		string stopMessage = string.init,
		string errorMessage = string.init
	)
	{
		_spawnedTid = spawn(&spinner, thisTid, startMessage, stopMessage, errorMessage);

		scope (exit)
		{
			send(_spawnedTid, StopSpinner(true, _exitCode));
			receive((bool done) {});
		}

		try
		{
			auto result = execute(cmd);
			_exitCode = result.status;
			return process(result.status, result.output);
		}
		catch (Exception e)
		{
			_error = e;
			_exitCode = 1;
			return false;
		}
	}
}
