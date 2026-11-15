import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
let size = 1024
let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat,_ g: CGFloat,_ b: CGFloat) -> CGColor { CGColor(red:r,green:g,blue:b,alpha:1) }
c.setFillColor(color(0.025,0.05,0.10)); c.fill(CGRect(x:0,y:0,width:size,height:size))
c.setFillColor(color(0.04,0.56,0.98))
for r in [CGRect(x:180,y:535,width:145,height:215),CGRect(x:345,y:640,width:145,height:220),CGRect(x:535,y:640,width:145,height:220),CGRect(x:700,y:535,width:145,height:215)] { c.fillEllipse(in:r) }
let pad=CGMutablePath();pad.move(to:CGPoint(x:240,y:330));pad.addQuadCurve(to:CGPoint(x:512,y:590),control:CGPoint(x:275,y:495));pad.addQuadCurve(to:CGPoint(x:784,y:330),control:CGPoint(x:755,y:495));pad.addQuadCurve(to:CGPoint(x:512,y:215),control:CGPoint(x:780,y:160));pad.addQuadCurve(to:CGPoint(x:240,y:330),control:CGPoint(x:245,y:160));pad.closeSubpath(); c.addPath(pad);c.fillPath()
c.setStrokeColor(color(1,1,1));c.setLineWidth(20);c.setLineJoin(.round);c.setLineCap(.round);c.move(to:CGPoint(x:290,y:350));for p in [CGPoint(x:410,y:350),CGPoint(x:455,y:425),CGPoint(x:510,y:285),CGPoint(x:570,y:390),CGPoint(x:610,y:350),CGPoint(x:730,y:350)] { c.addLine(to:p) };c.strokePath()
let dest=CGImageDestinationCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[1]) as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,c.makeImage()!,nil);guard CGImageDestinationFinalize(dest) else { exit(1) }
