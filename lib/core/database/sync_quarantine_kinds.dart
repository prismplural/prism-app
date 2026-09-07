const kConsumerDeliverySpillExpectedType = 'apply';
const kConsumerDeliverySpillApplyType = 'SpilledApply';
const kConsumerDeliverySpillDeleteType = 'SpilledDelete';
const kConsumerDeliverySpillErrorPrefix =
    'consumer-delivery journal over retention cap';
const kConsumerDeliverySpillErrorLike = '$kConsumerDeliverySpillErrorPrefix%';
const kConsumerDeliveryDeferredApplyType = 'DeferredSparseCreate';
const kConsumerDeliveryDeferredErrorPrefix =
    'consumer-delivery sparse create deferred';
const kConsumerDeliveryTombstoneType = 'ConsumerDeliveryTombstone';
