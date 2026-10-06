import MapKit
import SwiftUI

/// Place-card header (sheet drag area): eyebrow, name, × close. Focused for VoiceOver on appear.
struct DetailHeader: View {
    let restroom: Restroom
    let close: () -> Void
    @AccessibilityFocusState private var nameFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.unit) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restroom").themed(.label)
                Text(restroom.name.isEmpty ? "Restroom" : restroom.name).themed(.display)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true) // outside a ScrollView; keeps the text-clipped audit green
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("detail.name")
                    .accessibilityFocused($nameFocused)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Text("×").font(Theme.font(.display)).foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityHint("Shows the nearby restrooms again")
            .accessibilityIdentifier("detail.close")
        }
        .padding(.horizontal, 2 * Theme.unit)
        .padding(.bottom, Theme.unit)
        .onAppear { nameFocused = true }
    }
}

/// Scrolling place details with the Directions bar pinned to the bottom edge.
struct DetailView: View {
    let restroom: Restroom

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2 * Theme.unit) {
                    if !restroom.addressLine.isEmpty { Text(restroom.addressLine).themed(.body) }
                    if let d = restroom.distanceText {
                        Text(d).themed(.mono).accessibilityLabel(restroom.distanceSpoken ?? d)
                    }
                    if let a = restroom.access {
                        Hairline()
                        Text("Code").themed(.label).accessibilityAddTraits(.isHeader)
                        Group {
                            if case .code(let c) = a { Text(c).themed(.display) } else { Text(a.title).themed(.body) }
                        }
                        .accessibilityLabel(a.spoken)
                        .accessibilityIdentifier("detail.code")
                    }

                    Hairline()
                    if let tag = restroom.kind.tag {
                        Text(tag).themed(.label).accessibilityAddTraits(.isHeader)
                        Text("Parks and campgrounds usually have a public restroom. Not verified — from Apple Maps, not a restroom report.")
                            .themed(.body)
                            .accessibilityIdentifier("detail.kindNote")
                    } else if restroom.amenities.isEmpty {
                        Text("No amenity details").font(Theme.font(.body)).foregroundStyle(Theme.graphite)
                    } else {
                        ForEach(restroom.amenities, id: \.self) { a in
                            HStack(spacing: 2 * Theme.unit) {
                                Badge(kind: a, size: 20).accessibilityHidden(true)
                                Text(a.title).themed(.body)
                            }
                        }
                    }

                    if !restroom.directions.trimmingCharacters(in: .whitespaces).isEmpty {
                        Hairline()
                        Text("Directions").themed(.label).accessibilityAddTraits(.isHeader)
                        Text(restroom.directions).themed(.body)
                    }
                    if !restroom.comment.trimmingCharacters(in: .whitespaces).isEmpty {
                        Hairline()
                        Text("Notes").themed(.label).accessibilityAddTraits(.isHeader)
                        Text(restroom.comment).themed(.body)
                    }

                    if restroom.kind == .restroom {
                        Hairline()
                        Text("Votes").themed(.label).accessibilityAddTraits(.isHeader)
                        Text("\(restroom.upvote) up · \(restroom.downvote) down").themed(.mono)
                            .accessibilityLabel("\(restroom.upvote) upvotes, \(restroom.downvote) downvotes")
                    }

                    Button("Copy address") { UIPasteboard.general.string = restroom.addressLine }
                        .font(Theme.font(.title)).foregroundStyle(Theme.red)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .padding(.top, Theme.unit)
                        .accessibilityIdentifier("detail.copy")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(2 * Theme.unit)
            }
            Button(action: openDirections) {
                Text("Directions")
                    .font(Theme.font(.title))
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Rectangle().fill(Theme.red))
            }
            .accessibilityIdentifier("detail.directions")
        }
        .background(Theme.paper)
    }

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: restroom.coordinate))
        item.name = restroom.name.isEmpty ? "Restroom" : restroom.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
