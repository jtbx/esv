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

import std.conv      : to;
import std.exception : basicExceptionCtors, enforce;
import std.file      : tempDir, write;
import std.format    : format;
import std.json      : JSONValue, parseJSON;
import std.regex     : regex, matchAll, replaceAll;
import std.stdio     : File;
import std.string    : capitalize;
import std.net.curl  : HTTP;

enum ESVIndent
{
	SPACE,
	TAB
}

const enum string ESVAPI_URL = "https://api.esv.org/v3/passage";
const string[] BIBLE_BOOKS = [
	/* Old Testament */
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
	"Psalms", /* both are valid */
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
	/* New Testament */
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
/* All boolean API parameters */
const string[] ESVAPI_PARAMETERS = [
	"include-passage-references",
	"include-verse-numbers",
	"include-first-verse-numbers",
	"include-footnotes",
	"include-footnote-body",
	"include-headings",
	"include-short-copyright",
	"include-copyright",
	"include-passage-horizontal-lines",
	"include-heading-horizontal-lines",
	"include-selahs",
	"indent-poetry",
	"horizontal-line-length",
	"indent-paragraphs",
	"indent-poetry-lines",
	"indent-declares",
	"indent-psalm-doxology",
	"line-length",
	"indent-using",
];

/*
 * Returns true if the argument book is a valid book of the Bible.
 * Otherwise, returns false.
 */
bool bookValid(in char[] book) nothrow @safe
{
	foreach (string b; BIBLE_BOOKS) {
		if (book.capitalize() == b.capitalize())
			return true;
	}
	return false;
}
/*
 * Returns true if the argument book is a valid verse format.
 * Otherwise, returns false.
 */
bool verseValid(in char[] verse) @safe
{
	bool vMatch(in string re) @safe
	{
		return !verse.matchAll(regex(re)).empty;
	}
	if (vMatch("^\\d{1,3}$") ||
		vMatch("^\\d{1,3}-\\d{1,3}$") ||
		vMatch("^\\d{1,3}:\\d{1,3}$") ||
		vMatch("^\\d{1,3}:\\d{1,3}-\\d{1,3}$"))
		return true;

	return false;
}

}

class ESVApi
{
	protected {
		string _key;
		string _tmp;
		string _url;
	}

	string extraParameters;
	int delegate(size_t, size_t, size_t, size_t) onProgress;
	ESVApiOptions opts;

	this(string key, string tmpName = "esv")
	{
		_key = key;
		_tmp = tempDir() ~ tmpName;
		_url = ESVAPI_URL;
		opts = ESVApiOptions(true);
		extraParameters = "";
		onProgress = (size_t dlTotal, size_t dlNow, size_t ulTotal, size_t ulNow) { return 0; };
	}

	/*
	 * Returns the API authentication key that was given when the object
	 * was constructed. This authentication key cannot be changed.
	 */
	@property string key() const nothrow pure @safe
	{
		return _key;
	}
	/*
	 * Returns the subdirectory used to store temporary audio passages.
	 */
	@property string tmpDir() const nothrow pure @safe
	{
		return _tmp;
	}
	/*
	 * Returns the API URL currently in use.
	 */
	@property string url() const nothrow pure @safe
	{
		return _url;
	}
	/*
	 * Sets the API URL currently in use to the given url argument.
	 */
	@property void url(immutable(string) url) @safe
	in (!url.matchAll(`^https?://.+\\..+(/.+)?`).empty, "Invalid URL format")
	{
		_url = url;
	}
	/*
	 * Requests the verse(s) in text format from the API and returns it.
	 * The (case-insensitive) name of the book being searched are
	 * contained in the argument book. The verse(s) being looked up are
	 * contained in the argument verses.
	 *
	 * Example: getVerses("John", "3:16-21")
	 */
	string getVerses(in char[] book, in char[] verse) const
	in (bookValid(book),   "Invalid book")
	in (verseValid(verse), "Invalid verse format")
	{
		char[] params, response;
		HTTP   request;

		params = []; 

		{
			(char[])[] parambuf;
			foreach (string opt; ESVAPI_PARAMETERS) {
				bool bo;
				int io;

				switch (opt) {
				case "indent-using":
					o = opts.indent_using;
					break;
				case "indent-poetry":
				}
				!opt.matchAll("^include-").empty) {
					o = opts.b[opt];
				} else if (opt == "line-length" ||
				opt == "horizontal-line-length" ||
				!opt.matchAll("^indent-").empty) {
					o = opts.i[opt];
				}
				params = format!"%s&%s=%s"(params, opt, o.to!string());
			}
		}

		request = HTTP(
			format!"%s/text/?q=%s+%s%s%s"(_url, book
				.capitalize()
				.replaceAll(regex(" "), "+"),
			verse, params, extraParameters)
		);
		request.onProgress = onProgress;
		request.onReceive =
			(ubyte[] data)
			{
				response ~= data;
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
	 * Example: getAudioVerses("John", "3:16-21")
	 */
	string getAudioVerses(in char[] book, in char[] verse) const
	in (bookValid(book),   "Invalid book")
	in (verseValid(verse), "Invalid verse format")
	{
		char[] response;
		File   tmpFile;

		auto request = HTTP(format!"%s/audio/?q=%s+%s"(
			_url, book.capitalize().replaceAll(regex(" "), "+"), verse));
		request.onProgress = onProgress;
		request.onReceive =
			(ubyte[] data)
			{
				response ~= data;
				return data.length;
			};
		request.addRequestHeader("Authorization", "Token " ~ _key);
		request.perform();
		tmpFile = File(_tmp, "w");
		tmpFile.write(response);
		return _tmp;
	}
	/*
	 * Requests a passage search for the given query.
	 * If raw is false, formats the passage search as
	 * plain text, otherwise returns JSON from the API.
	 * 
	 * Example: search("It is finished")
	 */
	char[] search(in string query, in bool raw = true)
	{
		ulong  i;
		char[] response;
		char[] layout;
		HTTP   request;
		JSONValue json;

		request = HTTP(format!"%s/search/?q=%s"(
				_url, query.replaceAll(regex(" "), "+")));
		request.onProgress = onProgress;
		request.onReceive =
			(ubyte[] data)
			{
				response ~= cast(char[])data;
				return data.length;
			};
		request.addRequestHeader("Authorization", "Token " ~ _key);
		request.perform();

		if (raw)
			return response;

		json = response.parseJSON();
		layout = cast(char[])"";

		enforce!ESVException(json["total_results"].integer == 0, "No results for search");

		foreach (ulong i, JSONValue result; json["results"]) {
			layout ~= format!"%s\n    %s\n"(
				result["reference"].str,
				result["content"].str
			);
		}

		return layout;
	}
}

struct ESVApiOptions
{
	bool[string] b;
	int[string] i;
	ESVIndent indent_using;

	this(bool initialise) nothrow @safe
	{
		if (!initialise)
			return;

		b["include-passage-references"]  = true;
		b["include-verse-numbers"]       = true;
		b["include-first-verse-numbers"] = true;
		b["include-footnotes"]           = true;
		b["include-footnote-body"]       = true;
		b["include-headings"]            = true;
		b["include-short-copyright"]     = true;
		b["include-copyright"]           = false;
		b["include-passage-horizontal-lines"] = false;
		b["include-heading-horizontal-lines"] = false;
		b["include-selahs"] = true;
		b["indent-poetry"]  = true;
		i["horizontal-line-length"]	= 55;
		i["indent-paragraphs"]      = 2;
		i["indent-poetry-lines"]    = 4;
		i["indent-declares"]        = 40;
		i["indent-psalm-doxology"]  = 30;
		i["line-length"]            = 0;
		indent_using = ESVIndent.TAB;
	}
}

class ESVException : Exception
{
	mixin basicExceptionCtors;
}
