# Field notes: the Nordic light

Every spring the light comes back the same way and still surprises everyone. These are the
notes I keep while it happens — written in plain Markdown, in an ordinary file, on a disk I
own.

## What I record

The point of a field notebook is that it stays *legible* years later. So the vocabulary is
small: a **date**, a place, a measurement, and whatever I actually noticed. Anything more
elaborate rots. Anything less is a diary.

- Sunrise and sunset, to the minute
- Cloud cover, in eighths, the way sailors count it
- One sentence that is not about weather

![The 14 April sky, twenty minutes before the sun cleared the ridge](assets/showcase-sky.png)

### Two questions I keep returning to

1. Does the eye adapt to the returning light, or to its *rate of change*?
2. Why does the same 40 minutes read as "evening" in March and "afternoon" in June?

> The days are long, but the years are short — and in the north the days are long twice, once
> in the clock and once in the calendar.

## The measurements

| Date | Daylight | Cloud (8ths) | Note |
|---|---|---|---|
| 14 April | 14h 52m | 2 | First evening warm enough to sit outside |
| 28 April | 16h 21m | 6 | Swifts back over the harbour |
| 12 May | 17h 44m | 0 | Read outdoors until 22:30 without a lamp |

## Working with the file

The notebook is a folder of `.md` files and a folder of images beside them. Nothing else — no
database, no account, no export step. A tiny script rolls up the daylight column:

```swift
let minutes = entries.map(\.daylightMinutes)
let gained = minutes.max()! - minutes.min()!
print("gained \(gained / 60)h \(gained % 60)m since the first entry")
```

Which means the whole archive survives every tool I might use next — including
[the plain text editor](https://daringfireball.net/projects/markdown/) I started with.

## Still to do

- [x] Record the April entries
- [x] Photograph the 14 April sky
- [ ] Work out the ~~cloud~~ *visibility* column properly
- [ ] Compare against last year's notebook

---

Notes are kept in local time. Corrections belong in the file, not in a footnote.
