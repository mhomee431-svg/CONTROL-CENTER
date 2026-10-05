import sys; sys.path.insert(0,".")
import traceback
from app.services import pos_sync_service as p
from app.services.pos_integration import mock_provider as mp

mp.seed_catalog("mock-key-25", [{"pos_product_code":"A","name":"Rice 1kg","barcode":"890","price":10.0,"quantity":5}])
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.models.base import Base
from app.models.pos import *
from app.models.product import *
T=[POSIntegration.__table__,POSDevice.__table__,POSSyncJob.__table__,POSSyncLog.__table__,POSProductMapping.__table__,ProductMaster.__table__,ProductVariant.__table__,ProductIdentifier.__table__,ShopProduct.__table__,Inventory.__table__,InventoryMovement.__table__,PriceHistory.__table__]
e=create_engine("sqlite://"); Base.metadata.create_all(e,tables=T)
db=sessionmaker(bind=e)()
from app.services.pos_integration.base import POSProductRecord
integ=POSIntegration(shop_id=10,provider_name="Generic Till",integration_type="generic",auto_create_products=True)
db.add(integ); db.flush()
job=POSSyncJob(shop_id=10,integration_id=None,sync_type="FULL",trigger="T",status="RUNNING")
db.add(job); db.flush()
try:
    r=p._apply_record(db,integ,job,POSProductRecord(pos_product_code="A",name="Rice 1kg",sku=None,barcode=None,price=10.0,quantity=5),"fp")
    print("OK", r)
except Exception as ex:
    traceback.print_exc()
