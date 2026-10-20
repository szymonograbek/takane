import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code drawn crisp at any size.
struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .padding(16)
                .background(.white, in: .rect(cornerRadius: 16, style: .continuous))
        }
    }

    private static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
