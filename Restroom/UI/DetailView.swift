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
                    if !restroom.addressLine.isEmpty { Text(restroom.addressLine).themed(.body) }
                    if let d = restroom.distanceText { Text(d).themed(.mono) }

                    Hairline()
                    if restroom.amenities.isEmpty {
                        Text("No amenity details").font(Theme.font(.body)).foregroundStyle(Theme.graphite)
                    } else {
                        ForEach(restroom.amenities, id: \.self) { a in
                            HStack(spacing: 2 * Theme.unit) {
                                Badge(kind: a, size: 20)
                                Text(a.title).themed(.body)
                            }
                        }
                    }

                    if !restroom.directions.trimmingCharacters(in: .whitespaces).isEmpty {
                        Hairline()
                        Text("Directions").themed(.label)
                        Text(restroom.directions).themed(.body)
                    }
                    if !restroom.comment.trimmingCharacters(in: .whitespaces).isEmpty {
                        Hairline()
                        Text("Notes").themed(.label)
                        Text(restroom.comment).themed(.body)
                    }

                    Hairline()
                    Text("Votes").themed(.label)
                    Text("\(restroom.upvote) up · \(restroom.downvote) down").themed(.mono)

                    Button("Copy address") { UIPasteboard.general.string = restroom.addressLine }
                        .font(Theme.font(.title)).foregroundStyle(Theme.red)
                        .padding(.top, Theme.unit)
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
                    .frame(height: 56)
                    .background(Rectangle().fill(Theme.red))
            }
        }
        .background(Theme.paper)
    }

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: restroom.coordinate))
        item.name = restroom.name.isEmpty ? "Restroom" : restroom.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
