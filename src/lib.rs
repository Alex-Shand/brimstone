//! brimstone
#![warn(elided_lifetimes_in_paths)]
#![warn(missing_docs)]
#![warn(unreachable_pub)]
#![warn(unused_crate_dependencies)]
#![warn(unused_import_braces)]
#![warn(unused_lifetimes)]
#![warn(unused_qualifications)]
#![deny(unsafe_code)]
#![deny(unsafe_op_in_unsafe_fn)]
#![deny(unused_results)]
#![deny(missing_debug_implementations)]
#![deny(missing_copy_implementations)]
#![warn(clippy::pedantic)]
#![allow(clippy::doc_markdown)]
#![allow(clippy::let_underscore_untyped)]
#![allow(clippy::similar_names)]
#![allow(clippy::result_large_err)]
#![allow(clippy::struct_field_names)]
#![allow(clippy::missing_errors_doc)]

use std::{collections::HashMap, fs, iter};

use anyhow::{Context, Result, anyhow};
use camino::Utf8PathBuf as PathBuf;
use serde::{Deserialize, Serialize};
use toml::Value;

/// brimstone
#[allow(missing_copy_implementations)]
#[derive(Debug, argh::FromArgs)]
pub struct Args {
    /// output file
    #[argh(option)]
    out: PathBuf,
    #[argh(positional)]
    input: PathBuf,
    #[argh(positional)]
    inputs: Vec<PathBuf>,
}

#[allow(missing_docs)]
#[allow(clippy::missing_errors_doc)]
#[allow(clippy::missing_panics_doc)]
pub fn main(Args { out, input, inputs }: Args) -> Result<()> {
    let inputs = iter::once(input)
        .chain(inputs)
        .map(|input| {
            let contents = fs::read_to_string(&input)
                .with_context(|| anyhow!("Failed to read {input}"))?;
            toml::from_str(&contents)
                .with_context(|| anyhow!("Failed to parse {input}"))
        })
        .collect::<Result<Vec<Lockfile>>>()?;

    // This is probably a poor idea...
    let version = inputs
        .iter()
        .map(|i| i.version)
        .max()
        .expect("Inputs is always non-empty");

    let packages = inputs
        .into_iter()
        .flat_map(|i| i.packages)
        .fold(
            HashMap::<String, HashMap<String, Package>>::new(),
            |mut acc, package| {
                let _ = acc
                    .entry(package.name.clone())
                    .or_default()
                    .entry(package.version.clone())
                    .or_insert(package);
                acc
            },
        )
        .into_values()
        .flat_map(HashMap::into_values)
        .collect();

    let merged = Lockfile { version, packages };
    let merged = toml::to_string(&merged)
        .with_context(|| "Failed to serialize merged Lockfile")?;
    fs::write(&out, merged)
        .with_context(|| anyhow!("Failed to write to {out}"))?;

    Ok(())
}

#[derive(Debug, Serialize, Deserialize)]
struct Lockfile {
    version: usize,
    #[serde(rename = "package")]
    packages: Vec<Package>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Package {
    name: String,
    version: String,
    #[serde(flatten)]
    rest: HashMap<String, Value>,
}
