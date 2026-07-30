# Rich fixture

Smoke-screenshot-only fixture, compacted to fit the app's 720×560 default window with no
scrolling — see `Scripts/smoke-screenshot.sh` and `docs/ENGINEERING.md`'s ARC-Q13 entry for why:
every construct below must appear in the one screenshot this fixture exists to produce.

**Bold**, *italic*, ~~strikethrough~~, `inline code`. A [link](https://example.com) and image:

![sample image](assets/sample.png)

- Unordered item
  - Nested item
1. Ordered item
- [x] Done
- [ ] Open

> A blockquote.

```swift
func greet(_ name: String) -> String { "Hello, \(name)!" }
```

| Construct | Supported |
|---|---|
| Tables | yes |

---

Raw HTML, literal: <div>not executed</div>
