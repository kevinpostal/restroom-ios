import MapKit
import SwiftUI

struct DetailView: View {
    let restroom: Restroom

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2 * Theme.unit) {
                    Text("Restroom").themed(.label)
                    Text(restroom.name.isEmpty ? "Restroom" : restroom.name).themed(.display)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("detail.name")
                    if !restroom.addressLine.isEmpty { Text(restroom.addressLine).themed(.body) }
                    if let d = restroom.distanceText {
                        Text(d).themed(.mono).accessibilityLabel(restroom.distanceSpoken ?? d)
                    }

                    Hairline()
                    if restroom.amenities.isEmpty {
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

                    Hairline()
                    Text("Votes").themed(.label).accessibilityAddTraits(.isHeader)
                    Text("\(restroom.upvote) up · \(restroom.downvote) down").themed(.mono)
                        .accessibilityLabel("\(restroom.upvote) upvotes, \(restroom.downvote) downvotes")

                    Button("Copy address") { UIPasteboard.general.string = restroom.addressLine }
                        .font(Theme.font(.title)).foregroundStyle(Theme.red)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .padding(.top, Theme.unit)
                        .accessibilityIdentifier("detail.copy")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(2 * Theme.unit)
                .padding(.top, 2 * Theme.unit)
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
