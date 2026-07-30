# Smoke fixture — rich

Used only by `Scripts/smoke-screenshot.sh` for a one-time visual sanity screenshot alongside
process-level instrumentation. Not a functional parser or projection test fixture — those live
in `Markdown EditorTests`.

## Text formatting

Plain text with **bold**, *italic*, ***bold italic***, ~~strikethrough~~, and `inline code`.

## Links and images

A [link to an example](https://example.com) and a local image:

![sample image](assets/sample.png)

## Lists

- Unordered item one
- Unordered item two
  - Nested item

1. Ordered item one
2. Ordered item two

- [x] Completed task
- [ ] Open task

## Quote and code block

> A blockquote spanning
> two lines.

```swift
func greet(_ name: String) -> String {
    "Hello, \(name)!"
}
```

## Table

| Construct | Supported |
|---|---|
| Tables | yes |
| Task lists | yes |
| Strikethrough | yes |

---

Raw HTML shows literally, unformatted: <div>not executed</div>

Thematic break above; end of fixture.
