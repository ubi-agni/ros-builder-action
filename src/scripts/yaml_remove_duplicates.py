#!/usr/bin/env python3

import sys
import yaml

with open(sys.argv[1], 'r') as file:
    content = yaml.safe_load(file)

with open(sys.argv[1], 'w') as file:
    yaml.dump(content, file)
