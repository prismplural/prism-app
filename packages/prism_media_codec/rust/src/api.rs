pub fn codec_health_check() -> String {
    "prism_media_codec_ffi".to_string()
}

/// Resize and re-encode a static image into Prism's display-safe storage
/// formats.
///
/// Transparent input becomes lossless WebP. Opaque input becomes JPEG at the
/// requested quality. Animated formats must be handled before this function so
/// they are not flattened to a single frame.
pub fn encode_image(
    image_bytes: Vec<u8>,
    max_width: u32,
    max_height: u32,
    quality: u32,
) -> Result<(Vec<u8>, String), String> {
    use image::codecs::jpeg::JpegEncoder;
    use image::codecs::webp::WebPEncoder;
    use image::{ImageDecoder, ImageReader};
    use std::io::Cursor;

    let reader = ImageReader::new(Cursor::new(&image_bytes))
        .with_guessed_format()
        .map_err(|e| format!("Failed to read image: {e}"))?;

    let mut decoder = reader
        .into_decoder()
        .map_err(|e| format!("Failed to decode image: {e}"))?;
    let orientation = decoder
        .orientation()
        .map_err(|e| format!("Failed to read image orientation: {e}"))?;
    let mut img = image::DynamicImage::from_decoder(decoder)
        .map_err(|e| format!("Failed to decode image: {e}"))?;
    img.apply_orientation(orientation);

    let resized = if img.width() <= max_width && img.height() <= max_height {
        img
    } else {
        img.resize(max_width, max_height, image::imageops::FilterType::Lanczos3)
    };

    let rgba_buf = if resized.color().has_alpha() {
        let buf = resized.to_rgba8();
        let uses_alpha = buf.pixels().any(|p| p.0[3] != 255);
        if uses_alpha {
            Some(buf)
        } else {
            None
        }
    } else {
        None
    };

    let mut output = Vec::new();

    if let Some(rgba) = rgba_buf {
        WebPEncoder::new_lossless(&mut output)
            .encode(
                rgba.as_raw(),
                rgba.width(),
                rgba.height(),
                image::ExtendedColorType::Rgba8,
            )
            .map_err(|e| format!("Failed to encode WebP: {e}"))?;
        Ok((output, "image/webp".to_string()))
    } else {
        let rgb = resized.to_rgb8();
        JpegEncoder::new_with_quality(&mut output, quality.min(100) as u8)
            .encode(
                rgb.as_raw(),
                rgb.width(),
                rgb.height(),
                image::ExtendedColorType::Rgb8,
            )
            .map_err(|e| format!("Failed to encode JPEG: {e}"))?;
        Ok((output, "image/jpeg".to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::ImageEncoder;

    #[test]
    fn encode_image_emits_jpeg_for_opaque_input() {
        let source = image::RgbImage::from_pixel(12, 8, image::Rgb([20, 80, 140]));
        let mut png = Vec::new();
        image::codecs::png::PngEncoder::new(&mut png)
            .write_image(source.as_raw(), 12, 8, image::ExtendedColorType::Rgb8)
            .unwrap();

        let (encoded, mime_type) = encode_image(png, 24, 24, 85).unwrap();

        assert_eq!(mime_type, "image/jpeg");
        let image = image::load_from_memory(&encoded).unwrap();
        assert_eq!((image.width(), image.height()), (12, 8));
    }

    #[test]
    fn encode_image_emits_webp_for_transparent_input() {
        let source = image::RgbaImage::from_pixel(12, 8, image::Rgba([20, 80, 140, 120]));
        let mut png = Vec::new();
        image::codecs::png::PngEncoder::new(&mut png)
            .write_image(source.as_raw(), 12, 8, image::ExtendedColorType::Rgba8)
            .unwrap();

        let (encoded, mime_type) = encode_image(png, 24, 24, 85).unwrap();

        assert_eq!(mime_type, "image/webp");
        let image = image::load_from_memory(&encoded).unwrap();
        assert_eq!((image.width(), image.height()), (12, 8));
    }

    #[test]
    fn encode_image_accepts_static_gif_input() {
        let source = static_gif(2, 1);

        let (encoded, mime_type) = encode_image(source, 80, 80, 85).unwrap();

        assert_eq!(mime_type, "image/jpeg");
        let image = image::load_from_memory(&encoded).unwrap();
        assert_eq!((image.width(), image.height()), (2, 1));
    }

    #[test]
    fn encode_image_downscales_aspect_fit_without_upscaling() {
        let source = image::RgbImage::from_pixel(4000, 1000, image::Rgb([20, 80, 140]));
        let mut jpeg = Vec::new();
        image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg, 90)
            .write_image(
                source.as_raw(),
                source.width(),
                source.height(),
                image::ExtendedColorType::Rgb8,
            )
            .unwrap();

        let (encoded, mime_type) = encode_image(jpeg, 2048, 2048, 85).unwrap();

        assert_eq!(mime_type, "image/jpeg");
        let image = image::load_from_memory(&encoded).unwrap();
        assert_eq!((image.width(), image.height()), (2048, 512));
    }

    #[test]
    fn encode_image_applies_exif_orientation() {
        let source = jpeg_with_orientation_6(80, 40);

        let (encoded, mime_type) = encode_image(source, 80, 80, 85).unwrap();

        assert_eq!(mime_type, "image/jpeg");
        let image = image::load_from_memory(&encoded).unwrap();
        assert_eq!((image.width(), image.height()), (40, 80));
    }

    fn static_gif(width: u32, height: u32) -> Vec<u8> {
        use image::codecs::gif::GifEncoder;

        let source = image::RgbaImage::from_pixel(width, height, image::Rgba([20, 80, 140, 255]));
        let mut gif = Vec::new();
        GifEncoder::new(&mut gif)
            .encode(
                source.as_raw(),
                width,
                height,
                image::ExtendedColorType::Rgba8,
            )
            .unwrap();
        gif
    }

    fn jpeg_with_orientation_6(width: u32, height: u32) -> Vec<u8> {
        let source = image::RgbImage::from_pixel(width, height, image::Rgb([20, 80, 140]));
        let mut jpeg = Vec::new();
        image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg, 90)
            .write_image(
                source.as_raw(),
                width,
                height,
                image::ExtendedColorType::Rgb8,
            )
            .unwrap();
        assert_eq!(&jpeg[..2], &[0xff, 0xd8]);

        let app1 = [
            0xff, 0xe1, 0x00, 0x22, // APP1 marker + length.
            b'E', b'x', b'i', b'f', 0x00, 0x00, // Exif header.
            b'I', b'I', 0x2a, 0x00, // Little-endian TIFF header.
            0x08, 0x00, 0x00, 0x00, // IFD0 offset.
            0x01, 0x00, // One IFD entry.
            0x12, 0x01, // Orientation tag.
            0x03, 0x00, // SHORT.
            0x01, 0x00, 0x00, 0x00, // One value.
            0x06, 0x00, 0x00, 0x00, // Rotate 90 degrees clockwise.
            0x00, 0x00, 0x00, 0x00, // No next IFD.
        ];

        let mut out = Vec::with_capacity(jpeg.len() + app1.len());
        out.extend_from_slice(&jpeg[..2]);
        out.extend_from_slice(&app1);
        out.extend_from_slice(&jpeg[2..]);
        out
    }
}
