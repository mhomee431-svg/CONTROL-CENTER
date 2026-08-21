@echo off  
python -c "import pathlib; pathlib.Path('Backend/app/core/env.py').write_text(open('Backend/app/core/env_tmp.txt').read())" 
