#!/bin/bash

# Power off all ports 1–4 on hub 1-1
for p in 1 2 3 4; do
  sudo uhubctl -l 1-1 -p $p -a off
done

sleep 2

# Power on all ports 1–4 on hub 1-1
for p in 1 2 3 4; do
  sudo uhubctl -l 1-1 -p $p -a on
done

