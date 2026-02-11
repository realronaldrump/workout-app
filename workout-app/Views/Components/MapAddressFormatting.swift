import Foundation
import MapKit
import Contacts

func formatAddress(for mapItem: MKMapItem) -> String? {
    if #available(iOS 26.0, *) {
        if let fullAddress = mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullAddress.isEmpty {
            return fullAddress
        }

        if let shortAddress = mapItem.address?.shortAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shortAddress.isEmpty {
            return shortAddress
        }

        if let fullAddress = mapItem.address?.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullAddress.isEmpty {
            return fullAddress
        }
    }

    if #unavailable(iOS 26.0) {
        if let postalAddress = mapItem.placemark.postalAddress {
            let formatted = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty {
                return formatted
            }
        }

        let placemark = mapItem.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let city = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = placemark.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
        let postalCode = placemark.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines)

        let components = [street, city, region, postalCode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        if !components.isEmpty {
            return components.joined(separator: ", ")
        }

        if let title = placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
    }

    return nil
}
