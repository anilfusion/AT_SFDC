trigger ATFE_ProductMasterTrigger on Product2 (
    before insert,
    before update,
    after update
) {
    new MetadataTriggerHandler().run();
}