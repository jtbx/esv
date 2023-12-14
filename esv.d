/*
 * esv: read the Bible from your terminal
 *
 * The GPLv2 License (GPLv2)
 * Copyright (c) 2023 Jeremy Baxter
 * 
 * esv is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * esv is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with esv.  If not, see <http://www.gnu.org/licenses/>.
 */

module esv;

import std.conv    : to, ConvException;
import std.exception : enforce;
import std.file    : exists, mkdirRecurse, write, FileException;
import std.format  : format;
import std.getopt  : getopt, GetOptException;
import std.getopt  : getoptConfig = config;
import std.path    : baseName, dirName, expandTilde, isValidPath;
import std.process : environment, executeShell;
import std.regex   : regex, matchFirst, replaceAll, replaceFirst;
import std.stdio   : writef, writeln, writefln, stderr;
import std.string  : splitLines;

import config;
import esvapi;
import dini;

enum VERSION = "0.2.0";

bool   aFlag;        /* audio */
string CFlag;        /* config */
bool   fFlag, FFlag; /* footnotes */
bool   hFlag, HFlag; /* headings */
int    lFlag;        /* line length */
bool   nFlag, NFlag; /* verse numbers */
bool   rFlag, RFlag; /* passage references */
string sFlag;        /* search passages */
bool   VFlag;        /* show version */

version (OpenBSD) {
	immutable(char) *promises;
}

int
main(string[] args)
{
	bool success;

	version (OpenBSD) {
		import core.sys.openbsd.unistd : pledge;
		import std.string : toStringz;

		promises = toStringz("stdio rpath wpath cpath inet dns proc exec prot_exec");
		pledge(promises, null);
	}

	debug {
		return run(args) ? 0 : 1;
	}

	try {
		success = run(args);
	} catch (Exception e) {
		if (typeid(e) == typeid(Exception)) {
			stderr.writefln("%s: %s", args[0].baseName(), e.msg);
		} else {
			stderr.writefln("%s: uncaught %s in %s:%d: %s",
				args[0].baseName(),
				typeid(e).name,
				e.file, e.line, e.msg);
			stderr.writefln("this is probably a bug; it would be greatly appreciated if you reported it at:\n\n  %s",
				BUGREPORTURL);
		}
	}

	return success ? 0 : 1;
}

bool
run(string[] args)
{
	string apiKey;
	string configPath;
	Ini iniData;
	ESVApi esv;

	/* Parse command-line options */
	try {
		getopt(args,
			getoptConfig.bundling,
			getoptConfig.caseSensitive,
			"a", &aFlag,
			"C", &CFlag,
			"F", &FFlag, "f", &fFlag,
			"H", &HFlag, "h", &hFlag,
			"l", &lFlag,
			"N", &NFlag, "n", &nFlag,
			"R", &RFlag, "r", &rFlag,
			"s", &sFlag,
			"V", &VFlag,
		);
	} catch (GetOptException e) {
		enforce(e.msg.matchFirst(regex("^Unrecognized option")).empty,
			"unknown option " ~ e.extractOpt());
		enforce(e.msg.matchFirst(regex("^Missing value for argument")).empty,
			"missing argument for option " ~ e.extractOpt());

		throw new Exception(e.msg); /* catch-all */
	} catch (ConvException e) {
		throw new Exception(
			"illegal argument to -l option -- must be integer");
	}

	if (VFlag) {
		writeln("esv version " ~ VERSION);
		return true;
	}

	if (sFlag != "") {
		/* skip argument validation */
		goto config;
	}

	if (args.length < 3) {
		stderr.writefln("usage: %s [-aFfHhNnRrV] [-C config] [-l length] [-s query] book verses", args[0].baseName());
		return false;
	}

	enforce(bookValid(args[1].parseBook()),
		format!"book '%s' does not exist"(args[1]));
	enforce(verseValid(args[2]),
		format!"invalid verse format '%s'"(args[2]));

	/* determine configuration file
	 * Options have first priority, then environment variables,
	 * then the default path */
config:
	configPath = environment.get(ENV_CONFIG, DEFAULT_CONFIGPATH)
		.expandTilde();
	try {
		if (CFlag != "") { /* if -C was given */
			enforce(isValidPath(CFlag), CFlag ~ ": invalid path");
			configPath = CFlag.expandTilde();
		} else {
			enforce(isValidPath(configPath),
				configPath ~ ": invalid path");

			if (!configPath.exists()) {
				mkdirRecurse(configPath.dirName());
				configPath.write(format!
"# Default esv configuration file.

# An API key is required to access the ESV Bible API.
[api]
key = %s
# If you really need to, you can specify
# custom API parameters using `parameters`:
#parameters = &my-parameter=value

# Some other settings that modify how the passages are displayed:
#[passage]
#footnotes = false
#headings = false
#passage-references = false
#verse-numbers = false
"(DEFAULT_APIKEY));
			}
		}
		iniData = Ini.Parse(configPath);
	} catch (FileException e) {
		/* filesystem syscall errors */
		throw new Exception(e.msg);
	}
	try {
		apiKey = iniData["api"].getKey("key");
	} catch (IniException e) {
		apiKey = "";
	}
	enforce(apiKey != "",
		"API key not present in configuration file; cannot proceed");

	esv = new ESVApi(apiKey);

	enforce(!(aFlag && sFlag), "cannot specify both -a and -s options");
	if (aFlag) {
		string tmpf, mpegPlayer;

		tmpf = esv.getAudioPassage(args[1], args[2]);
		mpegPlayer = environment.get(ENV_PLAYER, DEFAULT_MPEGPLAYER);

		/* check for an audio player */
		enforce(
			executeShell(
				format!"command -v %s >/dev/null 2>&1"(mpegPlayer)
			).status == 0,
			format!"%s is required for audio mode; cannot continue"(mpegPlayer)
		);

		/* esv has built-in support for mpg123 and mpv.
		 * other players will work, just recompile with
		 * the DEFAULT_MPEGPLAYER enum set differently
		 * or use the ESV_PLAYER environment variable */
		mpegPlayer ~=
			mpegPlayer == "mpg123" ? " -q " :
			mpegPlayer == "mpv"    ? " --msg-level=all=no " : " ";
		/* spawn mpg123 */
		executeShell(mpegPlayer ~ tmpf);
		return true;
	}
	if (sFlag) {
		writeln(esv.searchFormat(sFlag));
		return true;
	}

	esv.extraParameters = iniData["api"].getKey("parameters");

	string
	returnValid(string def, string val) @safe
	{
		return val == "" ? def : val;
	}

	/* Get [passage] keys */
	foreach (string key; ["footnotes", "headings", "passage-references", "verse-numbers"]) {
		try {
			esv.opts.b["include-" ~ key] =
				returnValid("true", iniData["passage"].getKey(key)).to!bool();
		} catch (ConvException e) {
			throw new Exception(format!
				"%s: key '%s' of section 'passage' is not a boolean value (must be either 'true' or 'false')"
				(configPath, key)
			);
		} catch (IniException e) {} // just do nothing; use the default settings
	}
	/* Get line-length ([passage]) */
	try {
		esv.opts.i["line-length"] =
			returnValid("0", iniData["passage"].getKey("line-length")).to!int();
	}
	catch (ConvException e) {
		throw new Exception(
			format!"%s: illegal value '%s' -- must be an integer"(
				configPath,
				iniData["passage"].getKey("line-length"))
		);
	} catch (IniException e) {} // just do nothing; use the default setting

	if (fFlag) esv.opts.b["include-footnotes"]          = true;
	if (hFlag) esv.opts.b["include-headings"]           = true;
	if (nFlag) esv.opts.b["include-verse-numbers"]      = true;
	if (rFlag) esv.opts.b["include-passage-references"] = true;
	if (FFlag) esv.opts.b["include-footnotes"]          = false;
	if (HFlag) esv.opts.b["include-headings"]           = false;
	if (NFlag) esv.opts.b["include-verse-numbers"]      = false;
	if (RFlag) esv.opts.b["include-passage-references"] = false;
	if (lFlag != 0) esv.opts.i["line-length"] = lFlag;

	writeln(esv.getPassage(args[1].parseBook(), args[2]));
	return true;
}

private string
extractOpt(in GetOptException e) @safe
{
	return e.msg.matchFirst("-.")[0];
}

private string
parseBook(in string book) @safe
{
	return book.replaceAll(regex("[-_]"), " ");
}
