/*
 * esvapi.d: a reusable interface to the ESV HTTP API
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

module esvapi;

import std.algorithm : filter, map;
import std.array     : appender;
import std.ascii     : isAlphaNum;
import std.base64    : Base64;
import std.conv      : to;
import std.file      : mkdirRecurse, tempDir, write;
import std.format    : format;
import std.json      : JSONValue, parseJSON;
import std.random    : rndGen;
import std.range     : take;
import std.regex     : matchAll, replaceAll, replaceFirst, regex;
import std.string    : capitalize;
import std.utf       : toUTF8;
import std.net.curl;

public enum ESVMode
{
	TEXT,
	AUDIO
}

const enum ESVAPI_KEY = "abfb7456fa52ec4292c79e435890cfa3df14dc2b";
const enum ESVAPI_URL = "https://api.esv.org/v3/passage";
const string[] BIBLE_BOOKS = [
	// Old Testament
	"Genesis",
	"Exodus",
	"Leviticus",
	"Numbers",
	"Deuteronomy",
	"Joshua",
	"Judges",
	"Ruth",
	"1 Samuel",
	"2 Samuel",
	"1 Kings",
	"2 Kings",
	"1 Chronicles",
	"2 Chronicles",
	"Ezra",
	"Nehemiah",
	"Esther",
	"Job",
	"Psalm",
	"Psalms", // both are valid
	"Proverbs",
	"Ecclesiastes",
	"Song of Solomon",
	"Isaiah",
	"Jeremiah",
	"Lamentations",
	"Ezekiel",
	"Daniel",
	"Hosea",
	"Joel",
	"Amos",
	"Obadiah",
	"Jonah",
	"Micah",
	"Nahum",
	"Habakkuk",
	"Zephaniah",
	"Haggai",
	"Zechariah",
	"Malachi",
	// New Testament
	"Matthew",
	"Mark",
	"Luke",
	"John",
	"Acts",
	"Romans",
	"1 Corinthians",
	"2 Corinthians",
	"Galatians",
	"Ephesians",
	"Philippians",
	"Colossians",
	"1 Thessalonians",
	"2 Thessalonians",
	"1 Timothy",
	"2 Timothy",
	"Titus",
	"Philemon",
	"Hebrews",
	"James",
	"1 Peter",
	"2 Peter",
	"1 John",
	"2 John",
	"3 John",
	"Jude",
	"Revelation"
];

class ESVApi
{
	private {
		int _mode;
		string _key;
		string _tmp;
		string _url;
	}
	ESVApiOptions opts;
	string extraParameters;
	int delegate(size_t, size_t, size_t, size_t) onProgress;
	this(immutable(string) key = ESVAPI_KEY, bool audio = false)
	{
		_key  = key;
		_mode = audio ? ESVMode.AUDIO : ESVMode.TEXT;
		_tmp  = tempDir() ~ "esv";
		_url  = ESVAPI_URL;
		opts.defaults();
		extraParameters = "";
		onProgress = (size_t dlTotal, size_t dlNow, size_t ulTotal, size_t ulNow) { return 0; };
		tmpName = "esv";
	}
	/*
	 * Returns the API authentication key that was given when the API object was instantiated.
	 * This authentication key cannot be changed after instantiation.
	 */
	@nogc @property @safe string key() const nothrow
	{
		return _key;
	}
	/*
	 * Returns the API authentication key currently in use.
	 */
	@nogc @property @safe int mode() const nothrow
	{
		return _mode;
	}
	/*
	 * If the mode argument is either "text" or "html",
	 * sets the text API mode to the given mode argument.
	 * If the mode argument is not one of those,
	 * throws an ESVException.
	 */
	@property @safe void mode(immutable(int) mode)
	{
		if (mode == ESVMode.TEXT || mode == ESVMode.AUDIO)
			_mode = mode;
		else
			throw new ESVException("Invalid mode");
	}
	/*
	 * Returns the API URL currently in use.
	 */
	@nogc @property @safe string url() const nothrow
	{
		return _url;
	}
	/*
	 * If the url argument is a valid HTTP URL, sets the API URL currently in use
	 * to the given url argument. Otherwise, throws an ESVException.
	 */
	@property @safe void url(immutable(string) url)
	{
		if (url.matchAll("^https?://.+\\..+(/.+)?").empty)
			throw new ESVException("Invalid URL format");
		else
			_url = url;
	}
	/*
	 * Returns the temp directory name.
	 */
	@property @safe tmpName() const
	{
		return _tmp.replaceFirst(regex('^' ~ tempDir()), "");
	}
	/*
	 * Sets the temp directory name to the given string.
	 */
	@property @safe void tmpName(immutable(string) name)
	{
		_tmp = tempDir() ~ name;
	}
	/*
	 * Returns true if the argument book is a valid book of the Bible.
	 * Otherwise, returns false.
	 */
	@safe bool validateBook(in char[] book) const nothrow
	{
		foreach (b; BIBLE_BOOKS) {
			if (book.capitalize() == b.capitalize())
				return true;
		}
		return false;
	}
	/*
	 * Returns true if the argument book is a valid verse format.
	 * Otherwise, returns false.
	 */
	@safe bool validateVerse(in char[] verse) const
	{
		@safe bool attemptRegex(string re) const
		{
			return !verse.matchAll(re).empty;
		}
		if (attemptRegex("^\\d{1,3}$") ||
				attemptRegex("^\\d{1,3}-\\d{1,3}$") ||
				attemptRegex("^\\d{1,3}:\\d{1,3}$") ||
				attemptRegex("^\\d{1,3}:\\d{1,3}-\\d{1,3}$"))
			return true;
		else
			return false;
	}
	/*
	 * Requests the verse(s) from the API and returns it.
	 * The (case-insensitive) name of the book being searched are
	 * contained in the argument book. The verse(s) being looked up are
	 * contained in the argument verses.
	 *
	 * If the mode is ESVMode.AUDIO, requests an audio passage instead.
	 * A file path to an MP3 audio track is returned.
	 * To explicitly get an audio passage without setting the mode,
	 * use getAudioVerses().
	 * 
	 * Example: getVerses("John", "3:16-21")
	 */
	string getVerses(in char[] book, in char[] verse) const
	{
		if (_mode == ESVMode.AUDIO) {
			return getAudioVerses(book, verse);
		}

		if (!validateBook(book))
			throw new ESVException("Invalid book");
		if (!validateVerse(verse))
			throw new ESVException("Invalid verse format");

		string apiURL = format!"%s/%s/?q=%s+%s%s%s"(_url, _mode,
				book.capitalize().replaceAll(regex(" "), "+"), verse,
				assembleParameters(), extraParameters);
		auto request = HTTP(apiURL);
		string response;
		request.onProgress = onProgress;
		request.onReceive = (ubyte[] data)
		{
			response = cast(string)data;
			return data.length;
		};
		request.addRequestHeader("Authorization", "Token " ~ _key);
		request.perform();
		return response.parseJSON()["passages"][0].str;
	}
	/*
	 * Requests an audio track of the verse(s) from the API and
	 * returns a file path containing an MP3 sound track.
	 * The (case-insensitive) name of the book being searched are
	 * contained in the argument book. The verse(s) being looked up are
	 * contained in the argument verses.
	 * 
	 * Example: getVerses("John", "3:16-21")
	 */
	string getAudioVerses(in char[] book, in char[] verse) const
	{
		if (!validateBook(book))
			throw new ESVException("Invalid book");
		if (!validateVerse(verse))
			throw new ESVException("Invalid verse format");

		string apiURL = format!"%s/audio/?q=%s+%s"(_url, book.capitalize().replaceAll(regex(" "), "+"), verse);
		auto request = HTTP(apiURL);
		ubyte[] response;
		request.onProgress = onProgress;
		request.onReceive = (ubyte[] data)
		{
			response = response ~= data;
			return data.length;
		};
		request.addRequestHeader("Authorization", "Token " ~ _key);
		request.perform();
		string tmpFile = tempFile();
		tmpFile.write(response);
		return tmpFile;
	}
	private:
	@safe string assembleParameters() const
	{
		string params = "";
		string addParam(string param, string value) const
		{
			return format!"%s&%s=%s"(params, param, value);
		}
		params = addParam("include-passage-references",       opts.boolOpts["include_passage_references"].to!string);
		params = addParam("include-verse-numbers",            opts.boolOpts["include_verse_numbers"].to!string);
		params = addParam("include-first-verse-numbers",      opts.boolOpts["include_first_verse_numbers"].to!string);
		params = addParam("include-footnotes",                opts.boolOpts["include_footnotes"].to!string);
		params = addParam("include-footnote-body",            opts.boolOpts["include_footnote_body"].to!string);
		params = addParam("include-headings",                 opts.boolOpts["include_headings"].to!string);
		params = addParam("include-short-copyright",          opts.boolOpts["include_short_copyright"].to!string);
		params = addParam("include-copyright",                opts.boolOpts["include_copyright"].to!string);
		params = addParam("include-passage-horizontal-lines", opts.boolOpts["include_passage_horizontal_lines"].to!string);
		params = addParam("include-heading-horizontal-lines", opts.boolOpts["include_heading_horizontal_lines"].to!string);
		params = addParam("include-selahs",                   opts.boolOpts["include_selahs"].to!string);
		params = addParam("indent-poetry",                    opts.boolOpts["indent_poetry"].to!string);
		params = addParam("horizontal-line-length",           opts.intOpts ["horizontal_line_length"].to!string);
		params = addParam("indent-paragraphs",                opts.intOpts ["indent_paragraphs"].to!string);
		params = addParam("indent-poetry-lines",              opts.intOpts ["indent_poetry_lines"].to!string);
		params = addParam("indent-declares",                  opts.intOpts ["indent_declares"].to!string);
		params = addParam("indent-psalm-doxology",            opts.intOpts ["indent_psalm_doxology"].to!string);
		params = addParam("line-length",                      opts.intOpts ["line_length"].to!string);
		params = addParam("indent-using",                     opts.indent_using.to!string);
		return params;
	}
	@safe string tempFile() const
	{
		auto rndNums = rndGen().map!(a => cast(ubyte)a)().take(32);
		auto result = appender!string();
    	Base64.encode(rndNums, result);
		_tmp.mkdirRecurse();
		string f = _tmp ~ "/" ~ result.data.filter!isAlphaNum().to!string();
		return f;
	}
}

struct ESVApiOptions
{
	bool[string] boolOpts;
	int[string] intOpts;
	string indent_using;
	@safe void defaults() nothrow
	{
		boolOpts["include_passage_references"]       = true;
		boolOpts["include_verse_numbers"]            = true;
		boolOpts["include_first_verse_numbers"]      = true;
		boolOpts["include_footnotes"]                = true;
		boolOpts["include_footnote_body"]            = true;
		boolOpts["include_headings"]                 = true;
		boolOpts["include_short_copyright"]          = true;
		boolOpts["include_copyright"]                = false;
		boolOpts["include_passage_horizontal_lines"] = false;
		boolOpts["include_heading_horizontal_lines"] = false;
		boolOpts["include_selahs"]                   = true;
		boolOpts["indent_poetry"]                    = true;
		intOpts["horizontal_line_length"]			 = 55;
		intOpts["indent_paragraphs"]                 = 2;
		intOpts["indent_poetry_lines"]               = 4;
		intOpts["indent_declares"]                   = 40;
		intOpts["indent_psalm_doxology"]             = 30;
		intOpts["line_length"]                       = 0;
		indent_using                                 = "space";
	}
}

class ESVException : Exception
{
	@safe this(string msg, string file = __FILE__, size_t line = __LINE__) pure
	{
		super(msg, file, line);
	}
}
