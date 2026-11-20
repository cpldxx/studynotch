import AppKit
import Metal
import SwiftUI

/// Squat's face and pose as the numbers the shader reads. Every expression is one of these;
/// moving between two expressions mixes them.
struct MascotLook: Equatable {
    /// Eye colour, sRGB 0...1.
    var eye: SIMD3<Float>
    /// 1 is a full oval; lower narrows it (focus), higher widens it (drift).
    var open: Float = 1
    /// 0 ovals, 1 smile (a tall arch), 2 asleep (a shallow dip).
    var shape: Float = 0
    /// Where the eyes sit, about -1...1 on each axis; y grows upwards.
    var look = SIMD2<Float>(0, 0)
    var lean: Float = 0
    var squash: Float = 1
    /// The body turns a little toward the pointer (radians).
    var turn: Float = 0
    /// 0 open, 1 shut (only ovals blink).
    var blink: Float = 0
    /// An eyelid line across the top of each oval: its height in eye heights and its slope.
    /// A slope below 0 lowers the outer corners (sad), above 0 the inner ones (cross). Height 2 means none.
    var lid = SIMD2<Float>(2, 0)
    /// Half-width and half-height of the ovals, in body units. The user set these by hand.
    var eyeSize = SIMD2<Float>(0.075, 0.132)

    static let longEyes = SIMD2<Float>(0.07, 0.15)

    /// The eyes are always white (Island Text #F5F6F8). Moods change their shape, not their colour.
    static let white = SIMD3<Float>(0.961, 0.965, 0.973)

    static func of(_ mood: MascotMood) -> MascotLook {
        switch mood {
        case .rest: return MascotLook(eye: white)
        case .happy: return MascotLook(eye: white, shape: 1, look: [0, 0.2])
        case .thinking: return MascotLook(eye: white, open: 0.9, look: [0.9, 0.8], lean: -0.06)
        case .focus: return MascotLook(eye: white, open: 0.42, look: [0, -0.7], squash: 0.97)
        case .drift: return MascotLook(eye: white, open: 1.15, look: [-1, 0.2], lean: 0.09)
        case .sleep: return MascotLook(eye: white, shape: 2, look: [0, -0.3], squash: 0.92)
        case .proud: return MascotLook(eye: white, shape: 1, look: [0, 0.2], squash: 1.04)
        case .sad: return MascotLook(eye: white, open: 0.95, look: [0, -0.6], squash: 0.95, lid: [0.15, -0.9], eyeSize: longEyes)
        case .angry: return MascotLook(eye: white, open: 0.9, lid: [0.2, 1.1], eyeSize: longEyes)
        }
    }

    /// Part way from one look to the next. Numbers ease across; the eye shape (oval, smile,
    /// asleep) can't be mixed, so it swaps once, at `swap`, which the view times to a blink.
    static func mix(_ a: MascotLook, _ b: MascotLook, _ t: Float, swap: Float = 0.3) -> MascotLook {
        let k = max(0, min(1, t))
        func m(_ x: Float, _ y: Float) -> Float { x + (y - x) * k }
        var r = b
        r.eye = a.eye + (b.eye - a.eye) * k
        r.open = m(a.open, b.open)
        r.look = a.look + (b.look - a.look) * k
        r.lean = m(a.lean, b.lean)
        r.squash = m(a.squash, b.squash)
        r.turn = m(a.turn, b.turn)
        r.lid = a.lid + (b.lid - a.lid) * k
        r.eyeSize = a.eyeSize + (b.eyeSize - a.eyeSize) * k
        r.shape = k >= swap ? b.shape : a.shape
        return r
    }
}

/// Draws Squat in 3D with Metal (a system framework; no outside library). The shader is the same
/// program as the website's WebGL one in site/assets/squat.js: change both together.
/// Pictures come back as CGImages, so SwiftUI shows them like any image and `--render` can save them.
final class MascotRenderer {
    static let shared = MascotRenderer()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: [String: CGImage] = [:]

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "squatVertex")
            desc.fragmentFunction = library.makeFunction(name: "squatFragment")
            desc.colorAttachments[0].pixelFormat = .rgba8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            dlog("mascot shader failed: \(error.localizedDescription)")
            return nil
        }
        self.device = device
        self.queue = queue
    }

    /// The uniforms, laid out exactly like `U` in the shader.
    private struct Uniforms {
        var res: SIMD2<Float>
        var aa: Float
        var zoom: Float
        var eye: SIMD4<Float>
        var face: SIMD4<Float>
        var body: SIMD4<Float>
        var lid: SIMD4<Float>
    }

    /// A square picture `pixels` wide. Still frames are kept, so a resting mascot costs nothing.
    func image(_ look: MascotLook, pixels: Int, keep: Bool = true) -> CGImage? {
        let key = "\(pixels)|\(look)"
        if keep, let hit = cache[key] { return hit }
        guard let picture = render(look, pixels: max(8, pixels)) else { return nil }
        if keep {
            if cache.count > 80 { cache.removeAll() }
            cache[key] = picture
        }
        return picture
    }

    private func render(_ look: MascotLook, pixels: Int) -> CGImage? {
        let shared = device.hasUnifiedMemory
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: pixels, height: pixels, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = shared ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: desc), let buffer = queue.makeCommandBuffer() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var u = Uniforms(res: [Float(pixels), Float(pixels)], aa: 2, zoom: 1.9,
                         eye: SIMD4(look.eye, look.open),
                         face: [look.shape, look.look.x, look.look.y, look.blink],
                         body: [look.lean, look.squash, 0, look.turn],
                         lid: [look.lid.x, look.lid.y, look.eyeSize.x, look.eyeSize.y])
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if !shared, let blit = buffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        buffer.commit()
        buffer.waitUntilCompleted()

        let rowBytes = pixels * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * pixels)
        texture.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Squat as distances: one round body, lit by one studio.
    /// The eyes are not shapes; they are painted on the surface in a flat face plane, so they
    /// stay upright, perfect ovals however the body curves.
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct U {
      float2 res; float aa; float zoom;
      float4 eye;   // rgb, open
      float4 face;  // shape (0 oval, 1 smile, 2 asleep), look x, look y, blink
      float4 body;  // lean, squash, (unused), turn
      float4 lid;   // lid height, lid slope, eye half-width, eye half-height
    };

    struct VOut { float4 pos [[position]]; };

    vertex VOut squatVertex(uint vid [[vertex_id]]) {
      float2 p = float2(float((vid << 1) & 2), float(vid & 2));
      VOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); return o;
    }

    constant float R = 0.46;
    constant float C = 0.45;
    constant float YAW = 0.42;
    constant float PITCH = 0.22;

    float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
    float sdEllipsoid(float3 p, float3 r) { float k0 = length(p / r); float k1 = length(p / (r * r)); return k0 * (k0 - 1.0) / k1; }
    float sdRoundCone(float3 p, float3 a, float3 b, float r1, float r2) {
      float3 ba = b - a; float l2 = dot(ba, ba), rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1.0 / l2;
      float3 pa = p - a; float y = dot(pa, ba), z = y - l2;
      float3 xv = pa * l2 - ba * y; float x2 = dot(xv, xv), y2 = y * y * l2, z2 = z * z * l2;
      float k = sign(rr) * rr * rr * x2;
      if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
      if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
      return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
    }
    float2x2 rot(float a) { float c = cos(a), s = sin(a); return float2x2(float2(c, -s), float2(s, c)); }

    float3 bodySpace(float3 p, constant U& u) {
      p.xz = rot(u.body.w) * p.xz;
      p.xy = rot(u.body.x) * p.xy;
      p.y /= u.body.y;
      return p;
    }
    float body(float3 p, constant U& u) {
      return sdEllipsoid(p - float3(0.0, C, 0.0), float3(0.48, 0.45, 0.46));
    }
    float map(float3 p, constant U& u) { return body(bodySpace(p, u), u) * min(u.body.y, 1.0); }

    float2 facePlane(float3 b) {
      float3 F = float3(sin(YAW), 0.0, cos(YAW));
      float3 right = float3(F.z, 0.0, -F.x);
      float3 o = b - float3(0.0, C, 0.0);
      return float2(dot(o, right), o.y);
    }
    float taperArc(float2 q, float2 c, float r, float halfAng, float th, float up) {
      float2 v = q - c; v.y *= up;
      float a = clamp(atan2(v.x, v.y), -halfAng, halfAng);
      float2 p = r * float2(sin(a), cos(a));
      float w = th * mix(1.0, 0.16, pow(abs(a) / halfAng, 1.6));
      return length(v - p) - w;
    }
    float eyeDist(float2 f, constant U& u) {
      float d = 1e5;
      for (int i = 0; i < 2; i++) {
        float s = i == 0 ? -1.0 : 1.0;
        float2 c = float2(s * 0.17 + u.face.y * 0.06, 0.09 + u.face.z * 0.045);
        float2 q = f - c;
        float e;
        if (u.face.x < 0.5) {
          float2 r = float2(u.lid.z, u.lid.w * max(u.eye.w * (1.0 - u.face.w), 0.06));
          e = (length(q / r) - 1.0) * min(r.x, r.y);
          float xo = s * q.x;
          e = max(e, (q.y - (u.lid.x * r.y + u.lid.y * xo)) / sqrt(1.0 + u.lid.y * u.lid.y));
        } else if (u.face.x < 1.5) {
          e = taperArc(q / float2(1.15, 1.85), float2(0.0, -0.04), 0.066, 1.22, 0.019, 1.0) * 1.15;
        } else {
          e = taperArc(q, float2(0.0, 0.058), 0.086, 0.8, 0.021, -1.0);
        }
        d = min(d, e);
      }
      return d;
    }
    float3 normalAt(float3 p, constant U& u) {
      float2 e = float2(0.0006, 0.0);
      return normalize(float3(map(p + e.xyy, u) - map(p - e.xyy, u), map(p + e.yxy, u) - map(p - e.yxy, u), map(p + e.yyx, u) - map(p - e.yyx, u)));
    }
    float shadowAt(float3 ro, float3 rd, constant U& u) {
      float res = 1.0, t = 0.02;
      for (int i = 0; i < 48; i++) { float h = map(ro + rd * t, u); res = min(res, 5.0 * h / t); t += clamp(h, 0.008, 0.12); if (res < 0.002 || t > 3.0) break; }
      return clamp(res, 0.0, 1.0);
    }
    float occlusion(float3 p, float3 n, constant U& u) {
      float occ = 0.0, sca = 1.0;
      for (int i = 0; i < 6; i++) { float h = 0.012 + 0.15 * float(i) / 5.0; occ += (h - map(p + h * n, u)) * sca; sca *= 0.86; }
      return clamp(1.0 - 2.2 * occ, 0.0, 1.0);
    }
    float3 studio(float3 r) {
      float3 c = mix(float3(0.01), float3(0.02), smoothstep(-0.3, 0.7, r.y));
      c += float3(5.0, 4.9, 4.7) * smoothstep(0.84, 0.95, dot(r, normalize(float3(-0.6, 0.7, 0.4))));
      c += float3(1.6, 1.8, 2.2) * smoothstep(0.90, 0.985, dot(r, normalize(float3(0.85, 0.35, -0.4))));
      c += float3(0.6) * smoothstep(0.93, 0.99, dot(r, normalize(float3(0.2, 0.15, 1.0))));
      return c;
    }
    float3 toLin(float3 c) { return pow(c, float3(2.2)); }
    float3 aces(float3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }

    float4 shade(float2 frag, constant U& u) {
      float2 uv = (2.0 * frag - u.res) / u.res.y;
      float3 target = float3(0.0, 0.46, 0.0);
      float dist = 3.5 / u.zoom;
      float3 ro = target + dist * float3(sin(YAW) * cos(PITCH), sin(PITCH), cos(YAW) * cos(PITCH));
      float3 fw = normalize(target - ro), rt = normalize(cross(fw, float3(0, 1, 0))), up = cross(rt, fw);
      float3 rd = normalize(fw * 3.4 + uv.x * rt + uv.y * up);
      float t = 0.0; bool hit = false;
      for (int i = 0; i < 140; i++) {
        float h = map(ro + rd * t, u);
        if (abs(h) < 0.0004 * t) { hit = true; break; }
        t += h * 0.8;
        if (t > 12.0) break;
      }
      if (!hit) return float4(0.0);
      float3 p = ro + rd * t, n = normalAt(p, u);
      float3 L = normalize(float3(-0.45, 0.9, 0.5));
      float sh = shadowAt(p + n * 0.003, L, u);
      float occ = occlusion(p, n, u);
      float fre = pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 4.0);
      float3 eyeLin = toLin(u.eye.rgb);
      float3 b = bodySpace(p, u);
      float g = smoothstep(0.0, 1.0, b.y);
      float3 alb = mix(toLin(float3(0.035, 0.038, 0.045)), toLin(float3(0.11, 0.12, 0.14)), g);
      float dif = clamp(dot(n, L), 0.0, 1.0) * mix(1.0, sh, 0.85);
      float3 col = alb * (1.2 * dif + 0.25 * occ);
      float3 rimL = normalize(float3(0.8, 0.3, -0.6));
      col += float3(0.35, 0.42, 0.55) * pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 2.2) * clamp(dot(n, rimL) + 0.45, 0.0, 1.0) * occ;
      // The painted eyes, with an edge about one pixel wide at any size.
      float2 fp = facePlane(b);
      float3 nb = n; nb.xz = rot(u.body.w) * nb.xz; nb.xy = rot(u.body.x) * nb.xy;
      float front = smoothstep(0.1, 0.4, dot(nb, float3(sin(YAW), 0.0, cos(YAW))));
      float ed = eyeDist(fp, u);
      float edge = max(0.0025, 0.7 * dist / (3.4 * u.res.y));
      float mask = (1.0 - smoothstep(-edge, edge, ed)) * front;
      col += eyeLin * exp(-max(ed, 0.0) * 28.0) * 0.1 * front;
      col += eyeLin * 0.05 * smoothstep(0.35, 0.0, b.y) * occ;
      col = mix(col, eyeLin * 1.15, mask);
      float3 hal = normalize(L - rd);
      col += pow(clamp(dot(n, hal), 0.0, 1.0), 180.0) * 1.4 * sh;
      col = mix(col, studio(reflect(rd, n)) * occ, (0.045 + 0.85 * fre) * (1.0 - mask * 0.7));
      return float4(pow(aces(col), float3(1.0 / 2.2)), 1.0);
    }

    fragment float4 squatFragment(VOut in [[stage_in]], constant U& u [[buffer(0)]]) {
      float2 frag = float2(in.pos.x, u.res.y - in.pos.y);
      int n = u.aa > 1.5 ? 2 : 1;
      float4 acc = float4(0.0);
      for (int j = 0; j < n; j++) for (int i = 0; i < n; i++) {
        float2 o = n > 1 ? (float2(float(i), float(j)) - 0.5) * 0.5 : float2(0.0);
        float4 c = shade(frag + o, u);
        acc += float4(c.rgb * c.a, c.a);
      }
      return acc / float(n * n);
    }
    """
}
