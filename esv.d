/*
 * esv.d: a reusable interface to the ESV HTTP API
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
import std.regex     : matchAll, replaceAll, regex;
import std.string    : capitalize;
import std.utf       : toUTF8;
import std.net.curl;

const enum ESVAPI_URL = "https://api.esv.org/v3/passage";
const string[] ESVAPI_BIBLE_BOOKS = [
	// Old Testament
	"Genesis",
	"Exodus",
	"Leviticus",
	"Numbers",
	"Deuteronomy",
	"Joshua",
	"Judges",
	"Ruth",
	"1_Samuel",
	"2_Samuel",
	"1_Kings",
	"2_Kings",
	"1_Chronicles",
	"2_Chronicles",
	"Ezra",
	"Nehemiah",
	"Esther",
	"Job",
	"Psalm",  // <-
	"Psalms", // <- both are valid
	"Proverbs",
	"Ecclesiastes",
	"Song_of_Solomon",
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
	"1_Corinthians",
	"2_Corinthians",
	"Galatians",
	"Ephesians",
	"Philippians",
	"Colossians",
	"1_Thessalonians",
	"2_Thessalonians",
	"1_Timothy",
	"2_Timothy",
	"Titus",
	"Philemon",
	"Hebrews",
	"James",
	"1_Peter",
	"2_Peter",
	"1_John",
	"2_John",
	"3_John",
	"Jude",
	"Revelation"
];

class EsvAPI
{
	private string _key;
	private string _url;
	private string _mode;
	EsvAPIOptions opts;
	string extraParameters;
	int delegate(size_t dlTotal, size_t dlNow, size_t ulTotal, size_t ulNow) onProgress;
	string tmpDir;
	this(in string key)
	{
		this._url  = ESVAPI_URL;
		this._key  = key;
		this._mode = "text";
		this.opts.setDefaults();
		this.extraParameters = "";
		this.onProgress = (size_t dlTotal, size_t dlNow, size_t ulTotal, size_t ulNow) {return 0;};
		this.tmpDir = tempDir() ~ "esvapi";
	}
	/*
	 * Returns the API URL currently in use.
	 */
	final string getURL() const nothrow @nogc @safe
	{
		return _url;
	}
	/*
	 * If the url argument is a valid HTTP URL, sets the API URL currently in use
	 * to the given url argument. Otherwise, throws an EsvException .
	 */
	final void setURL(in string url) @safe
	{
		auto matches = url.matchAll("^https?://.+\\..+(/.+)?");
		if (matches.empty)
			throw new EsvException("Invalid URL format");
		else
			this._url = url;
	}
	/*
	 * Returns the API authentication key that was given when the API object was instantiated.
	 * This authentication key cannot be changed after instantiation.
	 */
	final string getKey() const nothrow @nogc @safe
	{
		return _key;
	}
	/*
	 * Returns the API authentication key currently in use.
	 */
	final string getMode() const nothrow @nogc @safe
	{
		return _mode;
	}
	/*
	 * If the mode argument is either "text" or "html",
	 * sets the text API mode to the given mode argument.
	 * If the mode argument is not one of those,
	 * then this function will do nothing.
	 */
	final void setMode(in string mode) nothrow @nogc @safe
	{
		foreach (string m; ["text", "html"] )
		{
			if (mode == m)
			{
				this._mode = mode;
				return;
			}
		}
	}
	/*
	 * Returns true if the argument book is a valid book of the Bible.
	 * Otherwise, returns false.
	 */
	final bool validateBook(in string book) const nothrow @safe
	{
		foreach (string b; ESVAPI_BIBLE_BOOKS)
		{
			if (book.capitalize() == b.capitalize())
				return true;
		}
		return false;
	}
	/*
	 * Returns true if the argument book is a valid verse format.
	 * Otherwise, returns false.
	 */
	final bool validateVerse(in string verse) const @safe
	{
		bool attemptRegex(string re) const @safe
		{
			auto matches = verse.matchAll(re);
			return !matches.empty;
		}
		if (attemptRegex("^\\d{1,3}$") ||
			attemptRegex("^\\d{1,3}-\\d{1,3}$") ||
			attemptRegex("^\\d{1,3}:\\d{1,3}$") ||
			attemptRegex("^\\d{1,3}:\\d{1,3}-\\d{1,3}$"))
		{
			return true;
		}
		else
		{
			return false;
		}
	}
	/*
	 * Requests the verse(s) from the API and returns it.
	 * The (case-insensitive) name of the book being searched are
	 * contained in the argument book. The verse(s) being looked up are
	 * contained in the argument verses.
	 * 
	 * Example: getVerses("John", "3:16-21")
	 */
	final string getVerses(in string book, in string verse) const
	{
		if (!this.validateBook(book))
			throw new EsvException("Invalid book");
		if (!this.validateVerse(verse))
			throw new EsvException("Invalid verse format");

		string apiURL = format!"%s/%s/?q=%s+%s%s%s"(this._url, this._mode,
				book.capitalize().replaceAll(regex("_"), "+"), verse, this.assembleParameters(), this.extraParameters);
		auto request = HTTP(apiURL);
		string response;
		request.onProgress = this.onProgress;
		request.onReceive = (ubyte[] data)
		{
			response = cast(string)data;
			return data.length;
		};
		request.addRequestHeader("Authorization", "Token " ~ this._key);
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
	final string getAudioVerses(in string book, in string verse) const
	{
		if (!this.validateBook(book))
			throw new EsvException("Invalid book");
		if (!this.validateVerse(verse))
			throw new EsvException("Invalid verse format");

		string apiURL = format!"%s/audio/?q=%s+%s"(this._url, book.capitalize().replaceAll(regex("_"), "+"), verse);
		auto request = HTTP(apiURL);
		ubyte[] response;
		request.onProgress = this.onProgress;
		request.onReceive = (ubyte[] data)
		{
			response = response ~= data;
			return data.length;
		};
		request.addRequestHeader("Authorization", "Token " ~ this._key);
		request.perform();
		string tmpFile = tempFile();
		tmpFile.write(response);
		return tmpFile;
	}
	private string assembleParameters() const @safe
	{
		string params = "";
		string addParam(string param, string value) const
		{
			return format!"%s&%s=%s"(params, param, value);
		}
		params = addParam("include-passage-references",       this.opts.boolOpts["include_passage_references"].to!string);
		params = addParam("include-verse-numbers",            this.opts.boolOpts["include_verse_numbers"].to!string);
		params = addParam("include-first-verse-numbers",      this.opts.boolOpts["include_first_verse_numbers"].to!string);
		params = addParam("include-footnotes",                this.opts.boolOpts["include_footnotes"].to!string);
		params = addParam("include-footnote-body",            this.opts.boolOpts["include_footnote_body"].to!string);
		params = addParam("include-headings",                 this.opts.boolOpts["include_headings"].to!string);
		params = addParam("include-short-copyright",          this.opts.boolOpts["include_short_copyright"].to!string);
		params = addParam("include-copyright",                this.opts.boolOpts["include_copyright"].to!string);
		params = addParam("include-passage-horizontal-lines", this.opts.boolOpts["include_passage_horizontal_lines"].to!string);
		params = addParam("include-heading-horizontal-lines", this.opts.boolOpts["include_heading_horizontal_lines"].to!string);
		params = addParam("include-selahs",                   this.opts.boolOpts["include_selahs"].to!string);
		params = addParam("indent-poetry",                    this.opts.boolOpts["indent_poetry"].to!string);
		params = addParam("horizontal-line-length",           this.opts.intOpts ["horizontal_line_length"].to!string);
		params = addParam("indent-paragraphs",                this.opts.intOpts ["indent_paragraphs"].to!string);
		params = addParam("indent-poetry-lines",              this.opts.intOpts ["indent_poetry_lines"].to!string);
		params = addParam("indent-declares",                  this.opts.intOpts ["indent_declares"].to!string);
		params = addParam("indent-psalm-doxology",            this.opts.intOpts ["indent_psalm_doxology"].to!string);
		params = addParam("line-length",                      this.opts.intOpts ["line_length"].to!string);
		params = addParam("indent-using",                     this.opts.indent_using.to!string);
		return params;
	}
	private string tempFile() const
	{
		auto rndNums = rndGen().map!(a => cast(ubyte)a)().take(32);
		auto result = appender!string();
    	Base64.encode(rndNums, result);
		this.tmpDir.mkdirRecurse();
		string f = this.tmpDir ~ "/" ~ result.data.filter!isAlphaNum().to!string();
		f.write("");
		return f;
	}
}

struct EsvAPIOptions
{
	bool[string] boolOpts;
	int[string] intOpts;
	string indent_using;
	void setDefaults() nothrow @safe
	{
		this.boolOpts["include_passage_references"]       = true;
		this.boolOpts["include_verse_numbers"]            = true;
		this.boolOpts["include_first_verse_numbers"]      = true;
		this.boolOpts["include_footnotes"]                = true;
		this.boolOpts["include_footnote_body"]            = true;
		this.boolOpts["include_headings"]                 = true;
		this.boolOpts["include_short_copyright"]          = true;
		this.boolOpts["include_copyright"]                = false;
		this.boolOpts["include_passage_horizontal_lines"] = false;
		this.boolOpts["include_heading_horizontal_lines"] = false;
		this.boolOpts["include_selahs"]                   = true;
		this.boolOpts["indent_poetry"]                    = true;
		this.intOpts["horizontal_line_length"]           = 55;
		this.intOpts["indent_paragraphs"]                = 2;
		this.intOpts["indent_poetry_lines"]              = 4;
		this.intOpts["indent_declares"]                  = 40;
		this.intOpts["indent_psalm_doxology"]            = 30;
		this.intOpts["line_length"]                      = 0;
		this.indent_using                     = "space";
	}
}

class EsvException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure
	{
		super(msg, file, line);
	}
}
