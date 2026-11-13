import XCTest

/// Rechenteile der Porter-Optik: Richtung eines Wechsels und Feder je Kante der Pille.
final class GlassEffectsTests: XCTestCase {
    func testDirectionFollowsIndexChange() {
        XCTAssertEqual(GlassMotion.direction(from: 0, to: 2), 1)
        XCTAssertEqual(GlassMotion.direction(from: 3, to: 1), -1)
        XCTAssertEqual(GlassMotion.direction(from: 1, to: 1), 0, "kein Wechsel")
        XCTAssertEqual(GlassMotion.direction(from: nil, to: 1), 0, "erster Auftritt gleitet nicht")
        XCTAssertEqual(GlassMotion.direction(from: 1, to: nil), 0)
    }

    func testLeadingEdgeIsTightTrailingEdgeIsSoft() {
        // Nach rechts: rechte Kante vorn (straff), linke hinten (weich) – die Pille dehnt sich.
        XCTAssertEqual(GlassMotion.role(direction: 1, rightEdge: true), .lead)
        XCTAssertEqual(GlassMotion.role(direction: 1, rightEdge: false), .trail)
        XCTAssertEqual(GlassMotion.role(direction: -1, rightEdge: false), .lead)
        XCTAssertEqual(GlassMotion.role(direction: -1, rightEdge: true), .trail)
        XCTAssertEqual(GlassMotion.role(direction: 0, rightEdge: true), .even)
        XCTAssertEqual(GlassMotion.role(direction: 0, rightEdge: false), .even)
    }

    func testRimPointLiesOnCapsuleOutline() {
        let size = CGSize(width: 120, height: 30)
        // Zeiger über der Mitte: Punkt oben auf dem Rand, waagrecht unter dem Zeiger.
        XCTAssertEqual(GlassMotion.rimPoint(toward: CGPoint(x: 60, y: -20), in: size), CGPoint(x: 60, y: 0))
        // Zeiger unten: Punkt auf der Unterkante.
        XCTAssertEqual(GlassMotion.rimPoint(toward: CGPoint(x: 50, y: 80), in: size), CGPoint(x: 50, y: 30))
        // Zeiger links außen auf Mittelhöhe: Spitze des linken Halbkreises.
        XCTAssertEqual(GlassMotion.rimPoint(toward: CGPoint(x: -40, y: 15), in: size), CGPoint(x: 0, y: 15))
        // Schräg rechts oben: genau ein Radius vom Mittelpunkt des rechten Halbkreises.
        let point = GlassMotion.rimPoint(toward: CGPoint(x: 200, y: -60), in: size)
        XCTAssertEqual(hypot(point.x - 105, point.y - 15), 15, accuracy: 0.0001)
        // Ohne Zeiger: Ruhelage auf der linken Schulter.
        XCTAssertEqual(GlassMotion.rimPoint(toward: nil, in: size), CGPoint(x: 16.5, y: 1))
    }
}
