#!/usr/bin/python3

import collections
import datetime
import itertools
import json
import os
import re
import stat
import sys
import urllib.parse
import urllib.request

import xml.sax.handler
import xml.sax.xmlreader
import xml.sax.saxutils


def datetime_from_iso(iso_s):
    if iso_s.endswith("Z"):
        iso_s = iso_s[:-1] + "+00:00"
    return datetime.datetime.fromisoformat(iso_s)


class XMLTVGenerator:
    def __init__(self):
        self.channels = set()

    @staticmethod
    def __sax_attrs(attrs={}):
        return xml.sax.xmlreader.AttributesImpl(attrs)

    @classmethod
    def __sax_generate_element(cls, handler, tag, attributes={}, text=None):
        handler.startElement(tag, cls.__sax_attrs(attributes))
        if text:
            handler.characters(text)
        handler.endElement(tag)

    def _dump_xmltv_channel(self, handler, channel):
        handler.startElement("channel", self.__sax_attrs({
            "id": channel.canonical_name
        }))

        self.__sax_generate_element(
            handler, "display-name", {
                "lang": channel.language
            },
            text=channel.name)
        self.__sax_generate_element(
            handler, "display-name",
            text=("%u" % (channel.ordernum)))
        # self.__sax_generate_element(
        #     handler, "display-name", {
        #         "lang": channel.language
        #     },
        #     text=("%u %s" % (channel.ordernum, channel.name)))

        self.__sax_generate_element(
            handler, "icon", {
                "src": channel.logo_url
            })

        handler.endElement("channel")

    def _dump_xmltv_programme(self, handler, programme):
        handler.startElement("programme", self.__sax_attrs({
            "channel": programme.channel.canonical_name,
            "start": programme.timeslot.lower.strftime("%Y%m%d%H%M%S %z"),
            "stop": programme.timeslot.upper.strftime("%Y%m%d%H%M%S %z")
        }))

        if programme.title:
            self.__sax_generate_element(handler, "title", {
                "lang": programme.channel.language  # assumption
            }, programme.title)

        if programme.sub_title:
            self.__sax_generate_element(handler, "sub-title", {
                "lang": programme.channel.language  # assumption
            }, programme.sub_title)

        if programme.desc:
            self.__sax_generate_element(handler, "desc", {
                "lang": programme.channel.language  # assumption
            }, programme.desc)

        if programme.credits:
            handler.startElement("credits", self.__sax_attrs({}))

            for credit in programme.credits:
                if credit.position in (
                        "actor", "adapter", "commentator", "composer",
                        "director", "editor", "guest", "presenter", "producer",
                        "writer"):
                    self.__sax_generate_element(
                        handler, credit.position, text=credit.name)
            handler.endElement("credits")

        if programme.date:
            self.__sax_generate_element(
                handler, "date", text=str(programme.date))

        for category in programme.categories:
            self.__sax_generate_element(handler, "category", {
                "lang": programme.channel.language  # assumption
            }, category)

        # true length?
        # length_secs = int((programme.timeslot.upper - programme.timeslot.lower).total_seconds())
        # self.__sax_generate_element(
        #     handler, "length", {"units": "seconds"},
        #     text=str(length_secs))

        for icon in programme.icons:
            try:
                icon_attrs = {
                    "src": icon
                }

                urlparts = urllib.parse.urlparse(icon)
                query_params = {
                    k: v
                    for (k, v) in (s.split("=", 2) for s in re.split("[&;]", urlparts.query))
                }

                if "w" in query_params:
                    icon_attrs["width"] = query_params["w"]
                if "h" in query_params:
                    icon_attrs["height"] = query_params["h"]

                self.__sax_generate_element(handler, "icon", icon_attrs)
                del icon_attrs
            except:
                pass

        if programme.country:
            self.__sax_generate_element(
                handler,
                "country",
                text=programme.country)

        if programme.episode_num:
            self.__sax_generate_element(
                handler,
                "episode-num",
                ({"system": programme.episode_num_system} if programme.episode_num_system else {}),
                programme.episode_num)

        if programme.premiere:
            self.__sax_generate_element(handler, "premiere")

        if programme.subtitles:
            self.__sax_generate_element(handler, "subtitles")

        if programme.rating:
            handler.startElement(
                "rating",
                self.__sax_attrs(
                    {"system": programme.rating_system} if programme.rating_system else {}))

            self.__sax_generate_element(handler, "value", text=programme.rating)

            handler.endElement("rating")

        if programme.star_rating:
            handler.startElement("star-rating", self.__sax_attrs({}))
            self.__sax_generate_element(
                handler, "value", text=programme.star_rating)
            handler.endElement("star-rating")

        handler.endElement("programme")

    def fromtv7epg(self, channels=None):
        if channels:
            self.source = itertools.chain.from_iterable(
                TV7EPG.forchannel(c) for c in channels)
        else:
            self.source = TV7EPG.allchannels()

    def dump(self, fd=sys.stdout):
        now = datetime.datetime.now(datetime.timezone.utc)

        xmlgen = xml.sax.saxutils.XMLGenerator(
            fd, encoding="utf-8", short_empty_elements=True)

        xmlgen.startDocument()

        xmlgen.startElement("tv", self.__sax_attrs({
            "generator-info-name": "tv7.py"
        }))

        for programme in self.source:
            if programme.timeslot.lower < now:
                continue

            if programme.channel.pk not in self.channels:
                try:
                    self._dump_xmltv_channel(xmlgen, programme.channel)
                    self.channels.add(programme.channel.pk)
                except e:
                    raise ValueError("Failed to dump channel", programme.channel) from e

            try:
                self._dump_xmltv_programme(xmlgen, programme)
            except e:
                raise ValueError("Failed to dump programme", programme) from e

        xmlgen.endElement("tv")

        xmlgen.endDocument()


class TV7EPGProgramme:
    Credit = collections.namedtuple("TV7EPGProgramme_Credit", (
        "position", "name"))
    Timeslot = collections.namedtuple("TV7EPGProgramme_Timeslot", (
        "lower", "upper", "bounds"))

    @classmethod
    def fromjson(cls, json):
        self = object.__new__(cls)

        self.pk = json["pk"]
        self.timeslot = cls.Timeslot(
            datetime_from_iso(json["timeslot"]["lower"]),
            datetime_from_iso(json["timeslot"]["upper"]),
            json["timeslot"]["bounds"])
        self.channel = TV7Channel.fromjson(json["channel"])
        self.title = json["title"]
        self.sub_title = json["sub_title"]
        self.desc = json["desc"]
        self.categories = json["categories"]
        self.country = json["country"]
        self.date = json["date"]
        self.icons = json["icons"]
        self.credits = [
            cls.Credit(c["position"], c["name"])
            for c in json["credits"]
        ]
        self.rating_system = json["rating_system"]
        self.rating = json["rating"]
        self.episode_num_system = json["episode_num_system"]
        self.episode_num = json["episode_num"]
        self.premiere = json["premiere"]
        self.subtitles = json["subtitles"]
        self.star_rating = json["star_rating"]

        return self

    def str(self):
        return json.dumps(vars(self), default=str)

    def repr(self):
        return str(self)


class TV7EPG:
    @classmethod
    def allchannels(cls):
        return map(TV7EPGProgramme.fromjson, TV7API()._paged_request("/epg/"))

    @classmethod
    def forchannel(cls, channel):
        return map(TV7EPGProgramme.fromjson, TV7API()._paged_request("/epg/?channel=" + channel.pk))


class TV7Channel:
    @classmethod
    def fromjson(cls, json):
        self = object.__new__(cls)

        self.pk = json["pk"]
        self.name = json["name"]
        self.hd = bool(json["hd"])
        self.mcast_src = json["src"]
        self.canonical_name = json["canonical_name"]
        self.logo_url = json["logo"]
        self.visible = bool(json["visible"])
        self.ordernum = int(json["ordernum"])
        self.langordernum = int(json["langordernum"])
        self.country = json["country"]
        self.language = json["language"]
        self.has_replay = json["has_replay"]
        self.hls_src = json["hls_src"]
        self.changed = datetime_from_iso(json["changed"])

        return self

    def __str__(self):
        return json.dumps(vars(self), default=str)

    def __repr__(self):
        return str(self)

    def epg(self):
        return TV7EPG.forchannel(self)


class TV7API:
    api_bases = {
        1: "https://api.tv.init7.net/api",
        2: "https://tv7api2.tv.init7.net/api",
    }

    def __init__(self, api_ver=1):
        self.api_base = self.api_bases[api_ver]

    def _paged_request(self, route):
        def _fetch_block(url):
            req = urllib.request.urlopen(url)
            resp = json.loads(req.read())

            results = resp.get("results", [])
            next_url = resp.get("next", None)
            return (results, next_url)

        next_url = self.api_base + route
        while next_url:
            (results, next_url) = _fetch_block(next_url)
            yield from results

    def channels(self):
        return map(TV7Channel.fromjson, self._paged_request("/tvchannel/"))

    def channel_by_name(self, name):
        results = list(self._paged_request(
            "/tvchannel/?canonical_name=" + urllib.parse.quote(name)))
        assert len(results) == 1, ("no channel %s" % (name))
        return TV7Channel.fromjson(results[0])


def generate_channel_m3u(url_type="mcast", extra=False):
    channels = TV7API().channels()

    yield "#EXTM3U"
    for ch in sorted(channels, key=lambda c: c.ordernum):
        attrs = {
            "tvg-name": ch.canonical_name,
            "tvg-logo": ch.logo_url,
            "group-title": ch.language,
        }
        if extra:
            attrs.update({
                "tvg-chno": ch.ordernum,
                "tvg-id": ch.canonical_name,
                "tvg-language": ch.language,
                "tvg-country": ch.country,
                "tvh-epg": "1",
            })

        yield '#EXTINF:0 %(attrs)s, %(chname)s' % {
            "attrs": " ".join('%s="%s"' % (k, v) for (k, v) in attrs.items()),
            "chname": ch.name,
        }
        yield getattr(ch, url_type+"_src")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        prog="tv7.py",
        epilog="This program is not endorsed by Init7 (yet :D).")
    subparsers = parser.add_subparsers(dest="command", required=True)

    parser_m3u = subparsers.add_parser("m3u", help="M3U playlist generator")
    parser_m3u.add_argument("--type", choices=["hls", "mcast"], default="hls")
    parser_m3u.add_argument("--extra", action="store_true", default=False)

    parser_xmltv = subparsers.add_parser("xmltv", help="XMLTV generator")
    parser_xmltv.add_argument("-o", type=str, dest="ofile", default="-")
    parser_xmltv.add_argument("channels", type=str, nargs="*")

    options = parser.parse_args()

    if "m3u" == options.command:
        kwargs = {"url_type": options.type, "extra": options.extra}
        print(*generate_channel_m3u(**kwargs), sep="\n")
    elif "xmltv" == options.command:
        if "-" == options.ofile:
            dest = sys.stdout
        elif os.path.exists(options.ofile) and stat.S_ISSOCK(os.stat(options.ofile).st_mode):
            import socket
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(options.ofile)
            dest = os.fdopen(sock.fileno(), "w")
        else:
            dest = open(options.ofile, "w")

        if options.channels:
            channels = map(TV7API().channel_by_name, options.channels)
        else:
            channels = None

        xmltvgen = XMLTVGenerator()
        xmltvgen.fromtv7epg(channels)
        xmltvgen.dump(dest)
