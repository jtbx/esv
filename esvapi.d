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
import std.regex     : regex, matchAll;
import std.stdio     : File;
import std.string    : capitalize, tr, wrap;
import std.net.curl  : HTTP;

/** Indentation style to use when formatting passages. */
enum ESVIndent
{
	SPACE,
	TAB
}

/** Default URL to use when sending API requests. */
enum string ESVAPI_URL = "https://api.esv.org/v3/passage";

/** Constant array of all books in the Bible. */
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

/** All allowed API parameters (for text passages). */
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

/**
 * Returns true if the argument book is a valid book of the Bible.
 * Otherwise, returns false.
 */
bool
bookValid(in char[] book) nothrow @safe
{
	foreach (string b; BIBLE_BOOKS) {
		if (book.capitalize() == b.capitalize())
			return true;
	}
	return false;
}
/**
 * Returns true if the argument verse is a valid verse format.
 * Otherwise, returns false.
 */
bool
verseValid(in char[] verse) @safe
{
	foreach (string re; [
		"^\\d{1,3}$",
		"^\\d{1,3}-\\d{1,3}$",
		"^\\d{1,3}:\\d{1,3}$",
		"^\\d{1,3}:\\d{1,3}-\\d{1,3}$"
	]) {
        if (!verse.matchAll(regex(re)).empty)
            return true;
	}

	return false;
}

/**
 * ESV API object containing the authentication key,
 * the API URL, any parameters to use when contacting the
 * API as well as the temporary directory to use when
 * fetching audio passages.
 */
class ESVApi
{
	protected {
		string _key;
		string _tmp;
		string _url;
	}

    /**
     * Structure that contains associative arrays for each of
     * the possible parameter types. Specify API parameters here.
     */
	ESVApiOptions opts;
    /**
     * Any additional parameters to append to the request.
     * Must start with an ampersand ('&').
     */
	string extraParameters;
    /**
     * Callback function that is called whenever progress is made
     * on a request.
     */
	int delegate(size_t, size_t, size_t, size_t) onProgress;

    /**
     * Constructs an ESVApi object using the given authentication key.
     */
	this(string key, string tmpName = "esv")
	{
		_key = key;
		_tmp = tempDir() ~ tmpName;
		_url = ESVAPI_URL;
		opts = ESVApiOptions(true);
		extraParameters = "";
		onProgress = delegate int (size_t dlTotal, size_t dlNow,
			size_t ulTotal, size_t ulNow)
        {
			return 0;
		};
	}

	/**
	 * Returns the API authentication key that was given when the object
	 * was constructed. This authentication key cannot be changed.
	 */
	@property string
	key() const nothrow pure @safe
	{
		return _key;
	}
	/**
	 * Returns the subdirectory used to store temporary audio passages.
	 */
	@property string
	tmpDir() const nothrow pure @safe
	{
		return _tmp;
	}
	/**
	 * Returns the API URL currently in use.
	 */
	@property string
	url() const nothrow pure @safe
	{
		return _url;
	}
	/**
	 * Sets the API URL currently in use to the given url argument.
	 */
	@property void
	url(immutable(string) url) @safe
	in (!url.matchAll(`^https?://.+\\..+(/.+)?`).empty, "Invalid URL format")
	{
		_url = url;
	}
	/**
	 * Requests the passage in text format from the API and returns it.
	 * The (case-insensitive) name of the book being searched are
	 * contained in the argument book. The verse(s) being looked up are
	 * contained in the argument verses.
	 *
	 * Example: getPassage("John", "3:16-21")
	 */
	string
	getPassage(in char[] book, in char[] verse)
	in (bookValid(book),   "Invalid book")
	in (verseValid(verse), "Invalid verse format")
	{
		char[] params, response;

		params = []; 

		{
			string[] parambuf;

			void
			addParams(R)(R item)
			{
				parambuf.length++;
				parambuf[parambuf.length - 1] =
					format!"&%s=%s"(item.key, item.value);
			}

			/*                    integers        booleans        indent_using */
			parambuf = new string[opts.i.length + opts.b.length + 1];

			foreach (item; opts.i.byKeyValue())
				addParams(item);
			foreach (item; opts.b.byKeyValue())
				addParams(item);

			parambuf[parambuf.length - 1] =
				format!"&indent-using=%s"(
					opts.indent_using == ESVIndent.TAB ? "tab" : "space");

			/* assemble string from string buffer */
			foreach (string param; parambuf) {
				params ~= param;
			}
		}

		response = makeRequest(format!"text/?q=%s+%s"(
			book
				.capitalize()
				.tr(" ", "+"),
			verse) ~ params ~ extraParameters);
		return response.parseJSON()["passages"][0].str;
	}
	/**
	 * Requests an audio track of the verse(s) from the API and
	 * returns a file path containing an MP3 sound track.
	 * The (case-insensitive) name of the book being searched are
	 * contained in the argument book. The verse(s) being looked up are
	 * contained in the argument verses.
	 * 
	 * Example: getAudioPassage("John", "3:16-21")
	 */
	string
	getAudioPassage(in char[] book, in char[] verse)
	in (bookValid(book),   "Invalid book")
	in (verseValid(verse), "Invalid verse format")
	{
		File tmpFile;

		tmpFile = File(_tmp, "w");
		tmpFile.write(makeRequest(format!"audio/?q=%s+%s"(
			book
				.capitalize()
				.tr(" ", "+"),
			verse)
		));
		return _tmp;
	}
	/**
	 * Requests a passage search for the given query.
	 * Returns a string containing JSON data representing
	 * the results of the search.
	 * 
	 * Example: search("It is finished")
	 */
	char[]
	search(in string query)
	{
		return makeRequest("search/?q=" ~ query.tr(" ", "+"));
	}
	/**
	 * Calls search() and formats the results nicely as plain text.
	 */
	char[]
	searchFormat(alias fmt = "\033[1m%s\033[0m\n  %s\n")
	(in string query, int lineLength = 0) /* 0 means default */
	{
		char[] layout;
		JSONValue resp;

		resp = parseJSON(search(query));
		layout = [];

		enforce!ESVException(resp["total_results"].integer != 0,
			"No results for search");

		lineLength = lineLength == 0 ? 80 : lineLength;

		foreach (JSONValue item; resp["results"].array) {
			layout ~= format!fmt(
				item["reference"].str,
				item["content"].str
					.wrap(lineLength)
			);
		}

		return layout;
	}

	protected char[]
	makeRequest(in char[] query)
	{
		char[] response;
		HTTP request;

		response = [];
		request = HTTP(_url ~ "/" ~ query);
		request.onProgress = onProgress;
		request.onReceive =
			(ubyte[] data)
			{
				response ~= data;
				return data.length;
			};
		request.addRequestHeader("Authorization", "Token " ~ _key);
		request.perform();

		return response;
	}
}

/**
 * Structure containing parameters passed to the ESV API.
 */
struct ESVApiOptions
{
    /** Boolean options */
	bool[string] b;
    /** Integer options */
	int[string] i;
    /** Indentation style to use when formatting text passages. */
	ESVIndent indent_using;

    /**
     * If initialise is true, initialise an ESVApiOptions
     * structure with the default values.
     */
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

/**
 * Exception thrown on API errors.
 * Currently only used when there is no search results
 * following a call of searchFormat.
 */
class ESVException : Exception
{
	mixin basicExceptionCtors;
}
