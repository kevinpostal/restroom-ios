# Restroom — find a public restroom nearby

Native iPhone app (SwiftUI, iOS 17+). Shows public restrooms around you — or around any place you
type — on a flat map and in a distance-sorted list, with accessibility / unisex / changing-table
flags, directions notes, and one-tap walking directions in Apple Maps.

Data: [Refuge Restrooms](https://www.refugerestrooms.org) open API (`/api/v1/restrooms/by_location`).

## Design

Dieter Rams × Bauhaus. As little design as possible: paper background, ink type, one red accent,
an 8-pt grid, hairline rules, zero corner radii, no shadows or gradients. Amenities are geometric
primitives — red circle (accessible), blue square (unisex), yellow triangle (changing table).
Distances are set in monospace. Section labels are tracked uppercase.

## Build

Requires Xcode 26 and [xcodegen](https://github.com/yonaskolb/XcodeGen). The `.xcodeproj` is generated, not committed.

```sh
make test     # xcodegen + unit tests on the iPhone 17 Pro simulator
make sim      # build, install and launch on the booted simulator
```

Set a simulator location first: `xcrun simctl location booted set 37.3349,-122.0090`.

## Deploy to a device

Needs an Apple ID in Xcode, the phone paired with Developer Mode on, and the profile trusted once
under Settings → General → VPN & Device Management.

```sh
make device   # UDID auto-detected from `xcrun devicectl list devices`
```

## Layout

- `Restroom/Design/Theme.swift` — colours, type scale, grid unit, geometric amenity badges.
- `Restroom/Model/` — `Restroom` (API model), `RefugeAPI`, `LocationService`, `FinderModel` (all state).
- `Restroom/UI/` — `FinderView` (header, search, map, list), `DetailView`.
- `RestroomTests/` — decoding fixture from the live API shape; `FinderModel` state transitions with a fake provider.
