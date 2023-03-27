/*
 * esv: read the Bible from your terminal
 *
 * The GPLv2 License (GPLv2)
 * Copyright (c) 2023 Jeremy Baxter
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import std.conv    : to, ConvException;
import std.file    : exists, write, FileException;
import std.getopt  : getopt, GetOptException, config;
import std.path    : baseName, expandTilde, isValidPath;
import std.process : environment, executeShell;
import std.regex   : regex, matchFirst, replaceFirst;
import std.stdio   : writef, writeln, writefln, stderr;
import std.string  : splitLines;

import esv;
import dini;

enum VERSION = "0.2.0";

enum DEFAULT_APIKEY     = "abfb7456fa52ec4292c79e435890cfa3df14dc2b"; // crossway approved ;)
enum DEFAULT_CONFIGPATH = "~/.config/esv.conf";
enum DEFAULT_MPEGPLAYER = "mpg123";
enum DEFAULT_PAGER      = "less";

enum ENV_CONFIG = "ESV_CONFIG";
enum ENV_PAGER  = "ESV_PAGER";
enum ENV_PLAYER = "ESV_PLAYER";

bool   optAudio;
string optConfigPath;
bool   optFootnotes;
bool   optNoFootnotes;
bool   optHeadings;
bool   optNoHeadings;
int    optLineLength = 0;
bool   optVerseNumbers;
bool   optNoVerseNumbers;
bool   optNoPager;
bool   optPassageReferences;
bool   optNoPassageReferences;
bool   optVersion;

int main(string[] args)
{
	void msg(string s)
	{
		stderr.writefln("%s: %s", args[0].baseName(), s);
	}

	void panic(string s)
	{
		import core.runtime     : Runtime;
		import core.stdc.stdlib : exit;

		msg(s);
		scope(exit) {
			Runtime.terminate();
			exit(1);
		}
	}

	// Parse command-line options
	try {
		args.getopt(
			config.bundling,
			config.caseSensitive,
			"a", &optAudio,
			"C", &optConfigPath,
			"F", &optNoFootnotes,
			"f", &optFootnotes,
			"H", &optNoHeadings,
			"h", &optHeadings,
			"l", &optLineLength,
			"N", &optNoVerseNumbers,
			"n", &optVerseNumbers,
			"P", &optNoPager,
			"R", &optNoPassageReferences,
			"r", &optNoPassageReferences,
			"V", &optVersion,
		);
	} catch (GetOptException e) {
		if (!e.msg.matchFirst(regex("^Unrecognized option")).empty)
			panic("unknown option " ~ e.extractOpt());
		else if (!e.msg.matchFirst(regex("^Missing value for argument")).empty)
			panic("missing argument for option " ~ e.extractOpt());
	} catch (ConvException e)
		panic("value provided by option -l is not convertible to an integer value; must be a non-decimal number");

	if (optVersion) {
		writeln("esv version " ~ VERSION);
		return 0;
	}

	if (args.length < 3) {
		stderr.writefln("usage: %s [-C config] [-l length] [-aFfHhNnPRrV] book verses", args[0].baseName());
		return 1;
	}

	// Determine configuration file
	// Options have first priority, then environment variables, then the default path
	string configPath;
	string configEnvVar = environment.get(ENV_CONFIG);
	Ini iniData;
	try {
		if (optConfigPath != "") {
			if (optConfigPath.isValidPath())
				configPath = optConfigPath.expandTilde();
			else
				panic(optConfigPath ~ ": invalid file path");
		} else {
			configPath = environment.get(ENV_CONFIG, DEFAULT_CONFIGPATH);
			if (configPath.isValidPath())
				configPath = configPath.expandTilde();
			else
				panic(configEnvVar ~ ": invalid file path");
			if (!configPath.exists()) {
				configPath.write(
"# Default esv configuration file.

# An API key is required to access the ESV Bible API.
[api]
key = " ~ DEFAULT_APIKEY ~ "
# If you really need to, you can specify
# custom API parameters using `parameters`:
#parameters = &my-parameter=value

# Some other settings that modify how the passages are displayed:
#[passage]
#footnotes = false
#headings = false
#passage_references = false
#verse_numbers = false
");
			}
		}
		iniData = Ini.Parse(configPath);
	} catch (FileException e) {
		// filesystem syscall errors
		if (!e.msg.matchFirst(regex("^" ~ configPath ~ ": [Ii]s a directory")).empty ||
			!e.msg.matchFirst(regex("^" ~ configPath ~ ": [Nn]o such file or directory")).empty ||
			!e.msg.matchFirst(regex("^" ~ configPath ~ ": [Pp]ermission denied")).empty)
			panic(e.msg);
	}
	string apiKey;
	try apiKey = iniData["api"].getKey("key");
	catch (IniException e)
		panic("API key not present in configuration file; cannot proceed");
	if (apiKey == "")
		panic("API key not present in configuration file; cannot proceed");

	// Initialise API object and validate the book and verse
	EsvAPI esv = new EsvAPI(apiKey);
	if (!esv.validateBook(args[1]))
		panic("book '" ~ args[1] ~ "' does not exist");
	if (!esv.validateVerse(args[2]))
		panic("invalid verse format '" ~ args[2] ~ "'");

	if (optAudio) {
		// check for mpg123
		if (executeShell("which " ~ DEFAULT_MPEGPLAYER ~ " >/dev/null 2>&1").status > 0) {
			panic(DEFAULT_MPEGPLAYER ~ " is required for audio mode; cannot continue");
			return 1;
		} else {
			string tmpf = esv.getAudioVerses(args[1], args[2]);
			string mpegPlayer = environment.get(ENV_PLAYER, DEFAULT_MPEGPLAYER);
			// esv has built-in support for mpg123 and mpv
			// other players will work, just recompile with
			// the DEFAULT_MPEGPLAYER enum set differently
			// or use the ESV_PLAYER environment variable
			if (mpegPlayer == "mpg123")
				mpegPlayer = mpegPlayer ~ " -q ";
			else if (mpegPlayer == "mpv")
				mpegPlayer = mpegPlayer ~ " --msg-level=all=no ";
			else
				mpegPlayer = DEFAULT_MPEGPLAYER ~ " ";
			// spawn mpg123
			executeShell(mpegPlayer ~ tmpf);
			return 0;
		}
	}

	esv.extraParameters = iniData["api"].getKey("parameters");

	string returnValid(string def, string val)
	{
		if (val == "")
			return def;
		else
			return val;
	}

	// Get [passage] keys
	foreach (string key; ["footnotes", "headings", "passage_references", "verse_numbers"]) {
		try {
			esv.opts.boolOpts["include_" ~ key] =
				returnValid("true", iniData["passage"].getKey(key)).catchConvException(
					(ConvException ex, string str)
					{
						panic(configPath ~ ": value '" ~ str ~
								"' is not convertible to a boolean value; must be either 'true' or 'false'");
					}
				);
		} catch (IniException e) {} // just do nothing; use the default settings
	}
	// Get line_length ([passage])
	try esv.opts.intOpts["line_length"] = returnValid("0",    iniData["passage"].getKey("line_length")).to!int();
	catch (ConvException e) {
		panic(configPath ~ ": value '" ~ iniData["passage"].getKey("line_length")
			~ "' is not convertible to an integer value; must be a non-decimal number");
	} catch (IniException e) {} // just do nothing; use the default setting

	if (optFootnotes)           esv.opts.boolOpts["include_footnotes"]          = true;
	if (optHeadings)            esv.opts.boolOpts["include_headings"]           = true;
	if (optVerseNumbers)        esv.opts.boolOpts["include_verse_numbers"]      = true;
	if (optPassageReferences)   esv.opts.boolOpts["include_passage_references"] = true;
	if (optNoFootnotes)         esv.opts.boolOpts["include_footnotes"]          = false;
	if (optNoHeadings)          esv.opts.boolOpts["include_headings"]           = false;
	if (optNoVerseNumbers)      esv.opts.boolOpts["include_verse_numbers"]      = false;
	if (optNoPassageReferences) esv.opts.boolOpts["include_passage_references"] = false;
	if (optLineLength != 0)     esv.opts.intOpts ["line_length"] = optLineLength;

	string verses = esv.getVerses(args[1], args[2]);
	int lines;
	foreach (string line; verses.splitLines())
		++lines;

	// If the passage is very long, pipe it into a pager
	if (lines > 32 && !optNoPager) {
		import std.process : pipeProcess, Redirect, wait, ProcessException;
		string pager = environment.get(ENV_PAGER, DEFAULT_PAGER);
		try {
			auto pipe = pipeProcess(pager, Redirect.stdin);
			pipe.stdin.writeln(verses);
			pipe.stdin.flush();
			pipe.stdin.close();
			pipe.pid.wait();
		}
		catch (ProcessException e) {
			if (!e.msg.matchFirst(regex("^Executable file not found")).empty) {
				panic(e.msg
						.matchFirst(": (.+)$")[0]
						.replaceFirst(regex("^: "), "")
						~ ": command not found"
				);
			}
		}
	} else
		writeln(verses);

	return 0;
}

string extractOpt(GetOptException e)
{
	return e.msg.matchFirst("-.")[0];
}

bool catchConvException(string sb, void delegate(ConvException ex, string str) catchNet)
{
	try return sb.to!bool();
	catch (ConvException e) {
		catchNet(e, sb);
		return false;
	}
}
