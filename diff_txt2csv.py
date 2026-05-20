#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Fri Feb  3 14:17:57 2023
@author: cvriend

Modified:
  - replaced deprecated read_csv(delim_whitespace=) with sep=r'\s+'
  - added logging, empty-file guard, no-files-found guard
  - os.chdir removed (use explicit paths throughout)
  - added --version flag
  - output directory created if it does not exist
  - informative exit codes
"""

import os
import sys
import logging
import argparse
import pandas as pd

__version__ = "1.1.0"

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(message)s"
)
log = logging.getLogger(__name__)


class UnexpectedNdiff(Exception):
    pass


# ── Diffusion map label sets ──────────────────────────────────────────────────
DIFF_LABELS = {
    4: ["AD", "FA", "MD", "RD"],
    7: ["AD", "FA", "MD", "RD", "OD", "ND", "FW"],
}


def parse_args():
    parser = argparse.ArgumentParser(
        description="Restructure per-tract diffusion txt files into a "
                    "single subject-level CSV table."
    )
    parser.add_argument(
        "--workdir", required=True,
        help="Directory containing the per-tract *_diffvalues.txt files"
    )
    parser.add_argument(
        "--outdir", required=True,
        help="Output directory for the subject CSV file"
    )
    parser.add_argument(
        "--subjid", required=True,
        help="Subject ID (used to match input files and name output)"
    )
    parser.add_argument(
        "--version", action="version", version=f"%(prog)s {__version__}"
    )
    return parser.parse_args()


def main():
    args = parse_args()

    workdir   = args.workdir
    outputdir = args.outdir
    subjid    = args.subjid

    # validate workdir
    if not os.path.isdir(workdir):
        log.error("workdir not found: %s", workdir)
        sys.exit(1)

    # create outputdir if needed
    os.makedirs(outputdir, exist_ok=True)

    # find all per-tract txt files for this subject
    diff_files = sorted(
        f for f in os.listdir(workdir)
        if f.startswith(subjid) and f.endswith("_diffvalues.txt")
    )

    if not diff_files:
        log.error(
            "No *_diffvalues.txt files found for subject '%s' in %s",
            subjid, workdir
        )
        sys.exit(1)

    log.info("Found %d tract file(s) for %s", len(diff_files), subjid)

    list_df = []

    for diff_file in diff_files:
        fpath = os.path.join(workdir, diff_file)

        # guard against empty files (e.g. fslstats returned nothing)
        if os.path.getsize(fpath) == 0:
            log.warning("Skipping empty file: %s", diff_file)
            continue

        # extract tract name from filename: sub-XXX_<tract>_diffvalues.txt
        tract_name = diff_file.replace(f"{subjid}_", "", 1).replace("_diffvalues.txt", "")

        df = pd.read_csv(fpath, sep=r"\s+", header=None)

        n_rows = df.shape[0]
        if n_rows not in DIFF_LABELS:
            raise UnexpectedNdiff(
                f"{diff_file}: unexpected number of diffusion measures "
                f"({n_rows}). Expected 4 (DTI only) or 7 (DTI + NODDI)."
            )

        df.columns = [tract_name]
        df["diff"] = DIFF_LABELS[n_rows]
        df = df.set_index("diff")

        list_df.append(df)

    if not list_df:
        log.error("All txt files were empty for subject %s", subjid)
        sys.exit(1)

    # concatenate all tracts into a single wide-format DataFrame
    df_out = pd.concat(list_df, axis=1)

    out_path = os.path.join(outputdir, f"{subjid}_diffvalues.csv")
    df_out.to_csv(out_path)

    log.info("CSV written: %s  (%d tracts x %d measures)",
             out_path, df_out.shape[1], df_out.shape[0])


if __name__ == "__main__":
    main()
