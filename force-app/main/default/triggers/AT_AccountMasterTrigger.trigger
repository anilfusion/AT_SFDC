trigger AT_AccountMasterTrigger on Account (
    before insert,
    after insert,
    before update
) {
    new MetadataTriggerHandler().run();
}