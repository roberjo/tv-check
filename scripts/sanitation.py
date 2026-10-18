"""City of LaGrange curbside schedule for Daybreak and the concierge.

Source: City of LaGrange "2026 Trash & Yard Trimming Schedule" flyer
(lagrangega.gov > Public Works > Trash & Recycling). Household garbage in the
city cart is collected every week on your day. On top of that the city
alternates weeks between YARD WASTE (leaves, brush, limbs; no grass clippings;
max 4 cu yd / 500 lb) and bulky TRASH (furniture, mattresses, bikes, swing sets;
max 2 cu yd / 400 lb). Weeks run Sunday-Saturday. Carts out by 7 AM on
collection day, back in by 7 AM the next day.

A city-observed holiday moves that day's pickup to the next day (per the
household; the flyer itself doesn't say). If the next day is also a holiday it
moves again, and a shift onto a weekend is flagged to confirm with the city.

Usage: python3 scripts/sanitation.py [YYYY-MM-DD] [weekday=Monday]
"""
import datetime as dt
import sys

# Shaded (yard waste) weeks on the flyer alternate strictly, starting with the
# week of Sunday 2025-12-28. Verified against all 53 weeks of the 2026 flyer.
YARD_WEEK_ANCHOR = dt.date(2025, 12, 28)
SCHEDULE_YEAR = 2026

CITY_HOLIDAYS = {  # red dates on the 2026 flyer
    dt.date(2026, 1, 1): "New Year's Day",
    dt.date(2026, 1, 19): "Martin Luther King Jr. Day",
    dt.date(2026, 5, 25): "Memorial Day",
    dt.date(2026, 6, 19): "Juneteenth",
    dt.date(2026, 7, 3): "Independence Day (observed)",
    dt.date(2026, 9, 7): "Labor Day",
    dt.date(2026, 11, 26): "Thanksgiving",
    dt.date(2026, 11, 27): "Day after Thanksgiving",
    dt.date(2026, 12, 24): "Christmas Eve",
    dt.date(2026, 12, 25): "Christmas Day",
}

YARD = {"kind": "yard", "label": "Yard waste week",
        "curb": "Leaves, brush and limbs (no grass clippings)", "limit": "4 cubic yards or 500 lb"}
BULKY = {"kind": "bulky", "label": "Bulky trash week",
         "curb": "Furniture, mattresses, bikes and other large items", "limit": "2 cubic yards or 400 lb"}
WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]


def week_start(day):
    return day - dt.timedelta(days=(day.weekday() + 1) % 7)  # back to Sunday


def extra_service(day):
    weeks = (week_start(day) - YARD_WEEK_ANCHOR).days // 7
    return YARD if weeks % 2 == 0 else BULKY


def next_pickup(today, weekday="Monday"):
    target = WEEKDAYS.index(weekday)
    scheduled = today + dt.timedelta(days=(target - today.weekday()) % 7)
    pickup = scheduled
    while pickup in CITY_HOLIDAYS:  # holiday pushes pickup to the next day
        pickup += dt.timedelta(days=1)
    if pickup < today:  # this week's shifted pickup already passed
        return next_pickup(scheduled + dt.timedelta(days=1), weekday)
    extra = extra_service(scheduled)
    holiday = CITY_HOLIDAYS.get(scheduled)
    return {
        "date": pickup.isoformat(),
        "scheduled_date": scheduled.isoformat(),
        "weekday": pickup.strftime("%A"),
        "days_away": (pickup - today).days,
        "garbage": True,
        "extra": extra,
        "holiday": holiday,
        "confirm_with_city": pickup.weekday() >= 5,
        "schedule_known": scheduled.year == SCHEDULE_YEAR,
        "reminder": reminder(pickup, scheduled, today, extra, holiday),
    }


def reminder(pickup, scheduled, today, extra, holiday):
    when = {0: "Today", 1: "Tomorrow"}.get((pickup - today).days, pickup.strftime("%A"))
    text = (f"{when}: garbage cart out by 7 AM, plus {extra['label'].lower()}: "
            f"{extra['curb'].lower()}, up to {extra['limit']}.")
    if holiday:
        text = (f"{scheduled:%A} is {holiday}, so pickup moves to {pickup:%A}. " + text)
        if pickup.weekday() >= 5:
            text += " Weekend pickup: confirm at 706-883-2100."
    return text


if __name__ == "__main__":
    today = dt.date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else dt.date.today()
    weekday = sys.argv[2] if len(sys.argv) > 2 else "Monday"
    import json
    print(json.dumps(next_pickup(today, weekday), indent=1))
