use std::{
    convert::TryInto,
    env::args,
    fs::{read, write},
    process,
};

const PNG_SIGNATURE: &[u8; 8] = b"\x89PNG\r\n\x1a\n";

/// PNG Chunk
/// type = 4-Byte Chunk code
/// data = Chunk Data
/// length = Length (usize)
///
/// See: https://www.libpng.org/pub/png/spec/1.2/PNG-Structure.html
struct PngChunk<'a> {
    chunk_type: &'a str,
    chunk_data: &'a [u8], // Unused but completes interface
    chunk_length: usize,
}

#[derive(Debug)]
enum PngError {
    NotEnoughBytes,
    InvalidLength,
    InvalidUTF8,
}

/// creates a PngChunk from bytes
///
/// Accepts bytes &\[u8\] as a chunk of bytes without the PNG Signature
fn read_png_chunk<'a>(bytes: &'a [u8]) -> Result<PngChunk<'a>, PngError> {
    let length_bytes = bytes.get(0..4).ok_or(PngError::NotEnoughBytes)?;

    let chunk_length: usize =
        u32::from_be_bytes(length_bytes.try_into().map_err(|_| PngError::InvalidUTF8)?) as usize;

    let chunk_type_bytes: &'a [u8; 4] = bytes
        .get(4..8)
        .ok_or(PngError::InvalidLength)?
        .try_into()
        .unwrap(); // Safe because hardcoded 4 bytes

    let chunk_type: &'a str =
        str::from_utf8(chunk_type_bytes).map_err(|_| PngError::InvalidUTF8)?;

    let chunk_data: &'a [u8] = bytes
        .get(8..8 + chunk_length)
        .ok_or(PngError::InvalidLength)?;

    Ok(PngChunk {
        chunk_type,
        chunk_length,
        chunk_data,
    })
}

fn main() {
    let args: Vec<String> = args().collect();

    let [_, input_path, output_path] = args.as_slice() else {
        eprintln!("Usage: hytale-icon-extractor <binary> <output-image>");
        process::exit(1);
    };

    // Read the Hytale Launcher Binary
    let bytes = match read(input_path) {
        Ok(res) => res,
        Err(err) => panic!("File read error: {err}"),
    };

    // Loop through all the windows with a PNG Sig
    'window_loop: for (png_start, window) in bytes.windows(PNG_SIGNATURE.len()).enumerate() {
        if window == PNG_SIGNATURE {
            let mut cursor: usize = png_start + PNG_SIGNATURE.len();

            // Check if first chunk is a legit chunk
            match read_png_chunk(&bytes[cursor..]) {
                Ok(res) => res,
                Err(err) => {
                    println!("Error Converting PNG Chunk: {err:?}");
                    continue;
                }
            };

            // Safe unwrap because hardcoded
            let width_bytes: [u8; 4] = bytes[cursor + 8..cursor + 12].try_into().unwrap();
            let height_bytes: [u8; 4] = bytes[cursor + 12..cursor + 16].try_into().unwrap();

            // Extract width and height from first chunk
            let width: u32 = u32::from_be_bytes(width_bytes);
            let height: u32 = u32::from_be_bytes(height_bytes);

            // We don't care about any images that aren't 256x256
            if width != 256 || height != 256 {
                eprintln!("Invalid image dimensions: {width}x{height}");
                continue; // Image not valid, find another one
            }

            let png_end = loop {
                let png_chunk = match read_png_chunk(&bytes[cursor..]) {
                    Ok(res) => res,
                    Err(err) => {
                        eprintln!("Error reading PNG chunk {err:?}");
                        continue 'window_loop;
                    }
                };
                cursor += 8 + png_chunk.chunk_length + 4;

                // IEND indicates end of PNG
                if png_chunk.chunk_type == "IEND" {
                    break cursor;
                }
            };

            if let Err(err) = write(output_path, &bytes[png_start..png_end]) {
                eprintln!("Failed to write image: {err}");
                process::exit(1);
            }
        }
    }
}
