use std::{fs, path::Path};

use anyhow::{Context, Result};

use crate::models::AttachmentFileType;

pub fn extract_text(file_path: &str, file_type: &AttachmentFileType) -> Result<String> {
    let path = Path::new(file_path);

    if !path.exists() {
        anyhow::bail!("attachment not found: {file_path}");
    }

    match file_type {
        AttachmentFileType::Txt => fs::read_to_string(path)
            .with_context(|| format!("failed to read text file {file_path}")),
        AttachmentFileType::Pdf => {
            let text = pdf_extract::extract_text(path)
                .with_context(|| format!("failed to extract pdf text from {file_path}"))?;
            Ok(text)
        }
    }
}
