             {item.shop_id != null && (
               <PermissionGuard capability={CAPABILITIES.SHOPS_READ} fallback={<Button size="small" disabled>Investigate</Button>}>
                 <Button
                   size="small"
                   startIcon={<Store size={14} />}
                   onClick={() => router.push(ROUTES.BUSINESS_DETAIL(item.shop_id))}
                 >
                   Investigate
                 </Button>
               </PermissionGuard>
             )}
             <PermissionGuard capability={CAPABILITIES.AUDIT_READ} fallback={<Button size="small" disabled>Audit</Button>}>
               <Button
                 size="small"
                 startIcon={<ScrollText size={14} />}
                 onClick={() => setAuditTarget(item)}
               >
                 Audit
               </Button>
             </PermissionGuard>