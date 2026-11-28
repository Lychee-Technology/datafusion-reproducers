// SPDX-License-Identifier: Apache-2.0

//! `datafusion = "=55.0.0"` pins only the facade crate: its own
//! dependencies on `datafusion-common` and the rest are caret requirements,
//! which a fresh resolution moves to the newest 55.x. The lockfile pins them
//! back (see the README); this test keeps a mixed build from being measured.

use std::collections::BTreeMap;

use deep_expression_planning::DATAFUSION_VERSION;

fn datafusion_packages() -> BTreeMap<String, Vec<String>> {
    let lock = include_str!("../Cargo.lock");
    let mut by_version: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let mut name = None;
    for line in lock.lines() {
        if let Some(n) = line.strip_prefix("name = ") {
            name = Some(n.trim_matches('"').to_string());
        } else if let Some(v) = line.strip_prefix("version = ")
            && let Some(n) = name.take()
            && n.starts_with("datafusion")
        {
            by_version
                .entry(v.trim_matches('"').to_string())
                .or_default()
                .push(n);
        }
    }
    by_version
}

#[test]
fn every_datafusion_crate_is_pinned_to_a_compared_release() {
    let by_version = datafusion_packages();
    let versions: Vec<_> = by_version.keys().map(String::as_str).collect();
    assert_eq!(versions, ["55.0.0", "56.0.0"], "{by_version:#?}");
    assert!(by_version["55.0.0"].contains(&"datafusion-physical-plan".to_string()));
    assert!(by_version["56.0.0"].contains(&"datafusion-physical-plan".to_string()));
}

#[test]
fn the_linked_release_is_one_of_them() {
    assert!(
        ["55.0.0", "56.0.0"].contains(&DATAFUSION_VERSION),
        "{DATAFUSION_VERSION}"
    );
}
