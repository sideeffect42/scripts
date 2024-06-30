#!/usr/bin/env python3

import csv
import enum
import json
import os
import random
import sys

from datetime import datetime
from itertools import count as Counter


class OinkoinCategoryType(enum.Enum):
    INCOME = 1
    EXPENSE = 0


def gen_oinkoin_data(in_records, map={}):
    id = Counter(start=1)
    records = []
    categories = {}

    def getcolumn(record, name, default=None, proc=None):
        mapval = map.get(name, name)
        if callable(mapval):
            v = record
            proc = mapval
        elif isinstance(mapval, (list, set, tuple)):
            v = next((record.get(k) for k in mapval if k in record), default)
        else:
            v = record.get(mapval, default)

        return proc(v) if callable(proc) else v

    for r in in_records:
        cat_name = getcolumn(r, "category_name", "")
        if cat_name not in categories:
            categories[cat_name] = {
                "name": cat_name,
                "color": ("255:%u:%u:%u" % (
                    random.randrange(50, 255, 1),
                    random.randrange(50, 255, 1),
                    random.randrange(50, 255, 1))),
                "icon": 63,  # question mark
                "category_type": (
                    getcolumn(r, "value", "0.00", proc=float) > 0.00
                    and OinkoinCategoryType.INCOME.value
                    or OinkoinCategoryType.EXPENSE.value)
                }

        records.append({
            "title": getcolumn(r, "title", ""),
            "value": getcolumn(r, "value", "0.00", float),
            "datetime": getcolumn(r, "datetime", int(datetime.now().timestamp()*1000)),
            "category_name": categories[cat_name]["name"],
            "category_type": categories[cat_name]["category_type"],
            "description": getcolumn(r, "description", "")
            })

    records.sort(key=lambda r: r["datetime"])

    for r in records:
        r["id"] = next(id)

    return json.dumps({
        "records": records,
        "categories": sorted(categories.values(), key=lambda c: c["name"]),
        "recurrent_record_patterns": [],
        "created_at": int(datetime.now().timestamp() * 1000)
        })


if __name__ == "__main__":
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r") as csvfile:
            # NOTE: even if ; is the wrong delimiter for CSV many apps use it.
            #       if your app is well-behaved and uses commas, replace the
            #       delimiter in the following line.
            in_records = csv.DictReader(csvfile, dialect="excel", delimiter=";")
            print(gen_oinkoin_data(in_records, {
                "title": ("title", "note"),
                "description": "description",
                "value": ("value", "amount", "money"),
                "datetime": lambda r: int((
                    datetime.fromtimestamp(int(r["timestamp"])) if "timestamp" in r else
                    datetime.fromisoformat(r["datetime"]) if "datetime" in r else
                    datetime.fromisoformat(r["date"]) if "date" in r else
                    datetime.fromtimestamp(0)
                    ).timestamp() * 1000),
                "category_name": "category"
                }))
    else:
        # empty JSON
        print(gen_oinkoin_data([]))
    
