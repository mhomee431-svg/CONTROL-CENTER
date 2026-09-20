#!/bin/bash
set -x

echo "=== Step 1: Find Backend directory ==="
cd /home/ubuntu/hyperlocal_app/backend 2>/dev/null || cd /home/ec2-user/hyperlocal_app/backend 2>/dev/null || cd /home/ubuntu/hyperlocal_customer_app/backend 2>/dev/null || cd /home/ec2-user/hyperlocal_customer_app/backend 2>/dev/null || cd /app/backend 2>/dev/null || { echo "ERROR: Backend directory not found"; ls /home/ubuntu /home/ec2-user /app 2>/dev/null; exit 1; }
echo "Backend dir: $(pwd)"

echo "=== Step 2: Fetch DATABASE_URL from SSM ==="
DB_URL=$(aws ssm get-parameter --name "/hyperlocal/production/database_url" --with-decryption --region ap-south-1 --query "Parameter.Value" --output text)
echo "URL fetched: OK"

echo "=== Step 3: Update .env ==="
sed -i "s|DATABASE_URL=.*|DATABASE_URL=$DB_URL|" .env
echo ".env updated"

echo "=== Step 4: Virtual environment ==="
if [ -d "venv" ]; then source venv/bin/activate; else python3 -m venv venv && source venv/bin/activate; fi
echo "VENV OK"

echo "=== Step 5: pip install ==="
pip install -r requirements.txt --quiet
echo "PIP DONE"

echo "=== Step 6: Alembic migrations ==="
alembic upgrade head
echo "MIGRATIONS DONE"

echo "=== Step 7: Seed categories ==="
python3 << 'PYEOF'
from app.services.merchant_category_seed import seed_merchant_categories
from app.database.session import SessionLocal
db = SessionLocal()
seed_merchant_categories(db)
db.commit()
db.close()
print("CATEGORIES_SEEDED_SUCCESSFULLY")
PYEOF

echo "=== Step 8: Start FastAPI server ==="
pkill -f "uvicorn app.main:app" 2>/dev/null || true
sleep 2
nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 > app.log 2>&1 &
echo "SERVER STARTING"
sleep 5

echo "=== Step 9: Health check ==="
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health)
echo "HEALTH_STATUS=$HTTP_STATUS"

echo "=== DEPLOYMENT_SCRIPT_COMPLETE ==="
