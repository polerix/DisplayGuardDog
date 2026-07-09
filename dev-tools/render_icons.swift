import AppKit

func drawSquare(_ rect: NSRect, lineWidth: CGFloat = 1.3) {
    let path = NSBezierPath(rect: rect)
    path.lineWidth = lineWidth
    NSColor.black.setStroke()
    path.stroke()
}

// Bold, chunky silhouette built for legibility at ~18-20px: one blended
// body+head blob, two stubby ears, one rear bump for a tail. No thin
// appendages (legs, tail curls) — they disappear at menu-bar scale.
// Facing left. All coordinates relative to an origin (nose tip roughly at x=0).
func drawDogcow(originX: CGFloat, originY: CGFloat, scale: CGFloat) {
    NSColor.black.setFill()

    // Body (barrel), overlapping generously with the head so they read as one blob.
    let bodyRect = NSRect(x: originX + 5*scale, y: originY, width: 16*scale, height: 11*scale)
    NSBezierPath(ovalIn: bodyRect).fill()

    // Head, overlapping the body's left end.
    let headRect = NSRect(x: originX, y: originY + 2*scale, width: 11*scale, height: 11*scale)
    NSBezierPath(ovalIn: headRect).fill()

    // Ears: two short, wide triangles merged into the head silhouette.
    let ear1 = NSBezierPath()
    ear1.move(to: NSPoint(x: originX + 1*scale, y: originY + 10*scale))
    ear1.line(to: NSPoint(x: originX + 2*scale, y: originY + 15*scale))
    ear1.line(to: NSPoint(x: originX + 5*scale, y: originY + 11*scale))
    ear1.close()
    ear1.fill()

    let ear2 = NSBezierPath()
    ear2.move(to: NSPoint(x: originX + 6*scale, y: originY + 11*scale))
    ear2.line(to: NSPoint(x: originX + 8.5*scale, y: originY + 15.5*scale))
    ear2.line(to: NSPoint(x: originX + 10*scale, y: originY + 10.5*scale))
    ear2.close()
    ear2.fill()

    // Tail: a rounded bump merged into the rear-top of the body, not a thin curl.
    let tailRect = NSRect(x: originX + 18*scale, y: originY + 7*scale, width: 5*scale, height: 5*scale)
    NSBezierPath(ovalIn: tailRect).fill()
}

// Final production canvas size (points) — matches what ships in the app.
let iconCanvasSize = NSSize(width: 26, height: 18)

func renderIcon(active: Bool) -> NSImage {
    let image = NSImage(size: iconCanvasSize, flipped: false) { rect in
        let squareSize: CGFloat = 11
        let squareY: CGFloat = 1

        if active {
            // Square on the right; dogcow's rear inside it, head/front sticking out to the left.
            let squareX = rect.width - squareSize - 1
            let squareRect = NSRect(x: squareX, y: squareY, width: squareSize, height: squareSize)
            let scale: CGFloat = 0.34
            // Position so the body/rear sits inside the square, head pokes out past squareX to the left.
            let originX = squareX - 5
            let originY = squareY + 2
            drawDogcow(originX: originX, originY: originY, scale: scale)
            drawSquare(squareRect)
        } else {
            // Dogcow fully inside a centered square.
            let squareX = (rect.width - squareSize) / 2
            let squareRect = NSRect(x: squareX, y: squareY, width: squareSize, height: squareSize)
            let scale: CGFloat = 0.26
            let originX = squareX + 1
            let originY = squareY + 2
            drawDogcow(originX: originX, originY: originY, scale: scale)
            drawSquare(squareRect)
        }
        return true
    }
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not render PNG")
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

savePNG(renderIcon(active: true), to: "/private/tmp/claude-501/-Users-polerixsys/90671e38-2713-4419-84d6-bba4e4d2341f/scratchpad/dogcow_active_true.png")
savePNG(renderIcon(active: false), to: "/private/tmp/claude-501/-Users-polerixsys/90671e38-2713-4419-84d6-bba4e4d2341f/scratchpad/dogcow_off_true.png")
print("done")
