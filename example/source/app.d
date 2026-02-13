import cmdspin;

import std.stdio : write, writeln;
import std.conv : to;
import std.algorithm : each;

// -------------------------
// Example 1: streaming mode
// -------------------------
// CmdSpinPipes runs a process via pipeProcess() and gives you two streams:
//   - pout: stdout of the child process
//   - perr: stderr of the child process
// You can read output incrementally while the spinner is running.
//
class Ping : CmdSpinPipes
{
private:
	string _ip;       // Target IP / host to ping
	int _count;       // Requested ping count (-c <count>)
	string[] _data;   // Collected stdout lines from ping

public:
	this(string ip, int count)
	{
		_ip = ip;
		_count = count;
	}

	// Returns collected output lines (stdout).
	string[] data()
	{
		return _data;
	}

	// Executes "ping" and streams its stdout line-by-line.
	bool exec()
	{
		return command(
			// External command to run:
			// ping -c <count> <ip>
			["ping", "-c", _count.to!string, _ip],

			// Callback called while the process is running.
			// You get stdout/stderr as File objects.
			(pout, perr)
			{
				int count = 0;

				foreach (line; pout.byLine)
				{
					_data ~= line.to!string;
					print(_data[$ - 1]);

					if (++count >= _count + 1)
					{
						// Send SIGTERM to the child process (if still running).
						terminatedProcess();
						return false;
					}
				}

				// If stdout is exhausted, the process likely ended.
				// Returning true here means the callback finished successfully;
				// overall success is typically decided by cmdspin using exitCode.
				return true;
			},

			// Spinner messages:
			"Start ping",                    // shown while running
			"Ping completed successfully",   // shown if exit code == 0
			"A problem occurred during ping" // shown otherwise
		);
	}
}

// ------------------------
// Example 2: capture mode
// ------------------------
// CmdSpinExecute runs a process via execute() and returns:
//   - exit status
//   - full captured output as a single string
//
class Hostname : CmdSpinExec
{
private:
	string _data; // Full output of "hostnamectl status"

public:
	// Returns captured output.
	string data()
	{
		return _data;
	}

	// Executes "hostnamectl status" and captures all output at once.
	bool exec()
	{
		return command(
			["hostnamectl", "status"],

			// Callback receives process exit status and captured output.
			(status, output)
			{
				_data = output;
				return status == 0; // treat exit code 0 as success
			},

			// Spinner messages:
			"Getting host status",
			"Status received",
			"A problem occurred while getting the status"
		);
	}
}

void main()
{
	// Run ping example.
	auto ping = new Ping("127.0.0.1", 5);
	ping.exec();

	// Print all collected ping lines after completion.
	ping.data().each!(l => l.writeln);

	// Print exit code
	// ping.getExitCode.writeln;

	// Run hostnamectl example.
	auto hostname = new Hostname();
	hostname.exec();

	// Print captured hostnamectl output.
	hostname.data().write;
}
