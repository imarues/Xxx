#!/bin/bash
set -euo pipefail

mkdir -p TurathSource/StoreReplica/Bridge
cp Integration/HiddenBatSignRuntime.swift TurathSource/StoreReplica/Bridge/HiddenBatSignRuntime.swift
python3 scripts/prepare-rich-turath-batsign.py
bash scripts/verify-rich-batsign-routing.sh
