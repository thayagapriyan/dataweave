%dw 2.0
output application/xml
import * from dw::core::Arrays
import mergeWith from dw::core::Objects
import last from dw::core::Strings
import java!java::util::concurrent::atomic::AtomicInteger

// ---------- Property Replacements as Variables ----------
var fixedAssetPnCategory = {
  serialized: ["ROT", "NON-ROT"]
}
var sap_invoice_prepaid = "EXP01"
var sap_originalReferenceDocumentType = "REF_DOC"
var sap_businessTransactionType = "BTT01"
var sap_accountingDocumentType_invoice = "INVOICE"
var sap_createdByUser = "system"
var sap_invoice_faGLAccount = "GLFA100"
var sap_profitCenter = "PC100"
var sap_invoice_faCostCenter = "CC200"
var sap_fixedasset_assetdata_item_subnumber = "SUB1"
// ...add other property replacements as needed
// ---------- End Property Replacement Vars ----------

var pnCategory = fixedAssetPnCategory
var counter = AtomicInteger::new(0)
fun increment() = Java::invoke('java.util.concurrent.atomic.AtomicInteger', 'incrementAndGet()', counter, {})

// Namespace
ns ns0 http://sap.com/xi/SAPSCORE/SFIN

fun sendSingleCreditorItem(items, orderType) = do {
    var CreditorItem = ((items partition (item) -> 
        if(orderType == "MEMO") (item.Amount contains "-") 
        else !(item.Amount contains "-")
    ).failure) reduce (
        (item, accumulator) -> 
            {"Amount": (item.Amount as Number + accumulator.Amount as Number) as String} 
            ++ ((item - "Amount") mergeWith (accumulator - "Amount"))
    )
    var Item = ((items partition (item) -> 
        if(orderType == "MEMO") (item.Amount contains "-") 
        else !(item.Amount contains "-")
    ).success) 
    ---
    Item ++ (if (isEmpty(CreditorItem)) [] else [CreditorItem])
}

fun sendPrepaidItems(items, orderType) = do {
    var g = items groupBy ((item, index) -> item.CreditDebitSequence) mapObject ((value, key, index) -> {
        (if(value.GLExpenditure contains sap_invoice_prepaid) "prepaid" else "notprepaid"): value
    })
    var j = (g.*prepaid default []) flatMap {
        $ map {
            (if(orderType != "MEMO") (
                if($.GLExpenditure contains sap_invoice_prepaid) "item" else "creditor"
            ) else (if ($.GLExpenditure contains sap_invoice_prepaid) "creditor" else "item")) : $
        }
    }
    var k = (g.*notprepaid default []) flatMap {
        $ map {
            (if(orderType != "MEMO") (
                if($.Amount contains "-") "creditor" else "item"
            ) else (if($.Amount contains "-") "item" else "creditor")) : $
        }
    }
    ---
    {
        item: (j.item default [] ) ++ (k.item default []),
        creditor: ((j.creditor default [] ) ++ (k.creditor default [])) reduce (
            (item, accumulator) -> 
                {"Amount": (item.Amount as Number + accumulator.Amount as Number) as String} 
                ++ ((item - "Amount") mergeWith (accumulator - "Amount"))
        )
    }
}

fun calcPennyDiff(amount, fixedAssetCount, index) = 
    if((amount mod fixedAssetCount) != 0 and (fixedAssetCount-1) == index)
        (
            (
                (amount/fixedAssetCount) as String {format: "#.##", roundMode : "FLOOR"} as Number 
                +
                (amount - ((amount/fixedAssetCount) as String {format: "#.##", roundMode : "FLOOR"} as Number * fixedAssetCount) ) 
            ) as String {format: "#.##", roundMode : "FLOOR"} as Number
        )
    else 
        ((amount/fixedAssetCount) as String {format: "#.##", roundMode : "FLOOR"} as Number)

---
ns0#JournalEntryBulkCreateRequest: {
    MessageHeader: {
        ID: "EXAMPLE_CORRELATION_ID",
        CreationDateTime: (now() as String {format: "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"})
    },
    (
        (payload default []) map using(
            header=$.JournalHeader,
            orderCategory=$.JournalHeader.TransactionCategory,
            companyCodeSize=sizeOf($.JournalHeader.AccountCode)
        ) {
        JournalEntryCreateRequest: {
            MessageHeader: {
                ID: $.JournalHeader.InvoiceVoucher,
                CreationDateTime: (now() as String {format: "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"})
            },
            JournalEntry: {
                OriginalReferenceDocumentType: sap_originalReferenceDocumentType,
                BusinessTransactionType: sap_businessTransactionType,
                AccountingDocumentType: sap_accountingDocumentType_invoice,                   
                DocumentHeaderText: ($.JournalHeader.OrderNumber default "") ++ "|" ++  ($.JournalHeader.OrderType default ""),
                CreatedByUser: sap_createdByUser,
                CompanyCode: $.JournalHeader.AccountCode,
                DocumentDate: $.JournalHeader.DocumentDate,
                PostingDate: if(!isEmpty($.JournalHeader.PostingDate))($.JournalHeader.PostingDate) else ((now() >> "PST") as Date),
                Reference1InDocumentHeader: last($.JournalHeader.Invoice, 20),
                Reference2InDocumentHeader: ($.JournalHeader.CreatedBy default "") ++ "|" ++ ($.JournalHeader.TransactionCategory default ""),
                (
                    if($.JournalItems.GLExpenditure contains sap_invoice_prepaid)
                        do {
                            var r = sendPrepaidItems($.JournalItems, orderCategory).creditor
                            ---
                            (
                                (sendPrepaidItems($.JournalItems, orderCategory).item map {
                                    Item: $.FixedAssetNumber map ((item, index) -> {
                                        ReferenceDocumentItem: increment(),
                                        GLAccount: if(
                                            $.GLExpenditure != sap_invoice_prepaid 
                                            and (pnCategory.serialized contains ($.PartNumberCategory)) 
                                            and !isEmpty($.FixedAssetCount)
                                        ) sap_invoice_faGLAccount else null,
                                        AmountInTransactionCurrency @(currencyCode: $.Currency): calcPennyDiff($.Amount as Number, $.FixedAssetCount default 1, index),
                                        DocumentItemText: ($.OrderLine default "") ++ "|" ++ ($.PartNumberCategory default ""),
                                        AccountAssignment: {
                                            (ProfitCenter: sap_profitCenter) if ($.LocationCode == "00"),			    
                                            PartnerSegment: "A0" ++ header.Terms,
                                            (
                                                if(
                                                    $.GLExpenditure != sap_invoice_prepaid 
                                                    and $.PartNumberCategory == "ROT" 
                                                    and header.CategoryCode == "PO/INVOICE" 
                                                    and isEmpty($.FixedAssetCount)
                                                ) 
                                                    (CostCenter: sap_invoice_faCostCenter) 
                                                else if ($.LocationCode != "00")
                                                    (CostCenter: (header.AccountCode[(companyCodeSize-2) to (companyCodeSize-1)] default "") ++ "" ++ ($.FinancialLocation default "") ++ "" ++ ($.LocationCode default "")) 
                                                else null
                                            ),
                                            (MasterFixedAsset: item) if(
                                                $.GLExpenditure != sap_invoice_prepaid
                                                and (pnCategory.serialized contains ($.PartNumberCategory)) 
                                                and ($.PartNumberCategory != "ROT_ENG") 
                                                and !isEmpty($.FixedAssetCount)
                                            ),
                                            (FixedAsset: sap_fixedasset_assetdata_item_subnumber) if( 
                                                $.GLExpenditure != sap_invoice_prepaid 
                                                and (pnCategory.serialized contains ($.PartNumberCategory)) 
                                                and ($.PartNumberCategory != "ROT_ENG")
                                            ),
                                            (FunctionalArea:  $.OrderCapitalExpediture) if $.OrderCapitalExpediture != null
                                        }
                                    })
                                })
                                ++ 
                                [
                                    {
                                        CreditorItem: {
                                            ReferenceDocumentItem: 1,
                                            Creditor: header.FinancialVendorCode,
                                            AmountInTransactionCurrency @(currencyCode: r.Currency): r.Amount
                                        }
                                    }
                                ]
                            )
                        }
                    else
                        sendSingleCreditorItem($.JournalItems, orderCategory) map {
                            (
                                if ($.Amount contains("-")) 
                                    (if(orderCategory =="MEMO") (
                                        Item: $.FixedAssetNumber map ((item, index) -> {
                                            ReferenceDocumentItem: increment(),
                                            GLAccount: if(
                                                (pnCategory.serialized contains ($.PartNumberCategory)) 
                                                and ($.PartNumberCategory != "ROT_ENG") 
                                                and !isEmpty($.FixedAssetCount)
                                            ) sap_invoice_faGLAccount else null,
                                            AmountInTransactionCurrency @(currencyCode: $.Currency): calcPennyDiff($.Amount as Number, $.FixedAssetCount default 1, index),
                                            DocumentItemText: ($.OrderLine default "") ++ "|" ++ ($.PartNumberCategory default ""),
                                            AccountAssignment: {
                                                (ProfitCenter: sap_profitCenter) if ($.LocationCode == "00"),			    
                                                PartnerSegment: "A0" ++ header.Terms,
                                                (
                                                    if(
                                                        $.PartNumberCategory == "ROT" 
                                                        and header.CategoryCode == "PO/INVOICE" 
                                                        and isEmpty($.FixedAssetCount)
                                                    ) 
                                                        (CostCenter: sap_invoice_faCostCenter) 
                                                    else if ($.LocationCode != "00")
                                                        (CostCenter: (header.AccountCode[(companyCodeSize-2) to (companyCodeSize-1)] default "") ++ "" ++ ($.FinancialLocation default "") ++ "" ++ ($.LocationCode default "")) 
                                                    else null
                                                ),
                                                (MasterFixedAsset: item) if(
                                                    (pnCategory.serialized contains ($.PartNumberCategory)) 
                                                    and ($.PartNumberCategory != "ROT_ENG")
                                                    and !isEmpty($.FixedAssetCount)
                                                ),
                                                (FixedAsset: sap_fixedasset_assetdata_item_subnumber) if (
                                                    (pnCategory.serialized contains ($.PartNumberCategory)) 
                                                    and ($.PartNumberCategory != "ROT_ENG")
                                                ),
                                                (FunctionalArea:  $.OrderCapitalExpediture) if $.OrderCapitalExpediture != null
                                            }
                                        })
                                    )
                                    else 
                                        CreditorItem: {
                                            ReferenceDocumentItem: increment(),
                                            Creditor: header.FinancialVendorCode,
                                            AmountInTransactionCurrency @(currencyCode: $.Currency): ($.Amount as Number {format: "#.##", roundMode : "CEILING"})
                                        }
                                    )
                                else if(orderCategory =="MEMO")
                                    CreditorItem: {
                                        ReferenceDocumentItem: increment(),
                                        Creditor: header.FinancialVendorCode,
                                        AmountInTransactionCurrency @(currencyCode: $.Currency): ($.Amount as Number {format: "#.##", roundMode : "CEILING"})
                                    }
                                else
                                    Item: $.FixedAssetNumber map ((item, index) -> {
                                        ReferenceDocumentItem: increment(),
                                        GLAccount: if(
                                            (pnCategory.serialized contains ($.PartNumberCategory)) 
                                            and ($.PartNumberCategory != "ROT_ENG") 
                                            and !isEmpty($.FixedAssetCount)
                                        ) sap_invoice_faGLAccount else null,
                                        AmountInTransactionCurrency @(currencyCode: $.Currency): calcPennyDiff($.Amount as Number, $.FixedAssetCount default 1, index),
                                        DocumentItemText: ($.OrderLine default "") ++ "|" ++ ($.PartNumberCategory default ""),
                                        AccountAssignment: {
                                            (ProfitCenter: sap_profitCenter) if ($.LocationCode == "00"),
                                            PartnerSegment: "A0" ++ header.Terms,
                                            (
                                                if(orderCategory == "ORDER" and $.PartNumberCategory == "ROT" and header.CategoryCode == "PO/INVOICE" and isEmpty($.FixedAssetCount)) 
                                                    (CostCenter: sap_invoice_faCostCenter)
                                                else if ($.LocationCode != "00")
                                                    (CostCenter: (header.AccountCode[(companyCodeSize-2) to (companyCodeSize-1)] default "") ++ "" ++ ($.FinancialLocation default "") ++ "" ++ ($.LocationCode default ""))
                                                else null
                                            ),
                                            (MasterFixedAsset: item) if(
                                                (pnCategory.serialized contains ($.PartNumberCategory))
                                                and ($.PartNumberCategory != "ROT_ENG")
                                                and !isEmpty($.FixedAssetCount)
                                            ),  
                                            (FixedAsset: sap_fixedasset_assetdata_item_subnumber) if (
                                                (pnCategory.serialized contains ($.PartNumberCategory))
                                                and ($.PartNumberCategory != "ROT_ENG")
                                            ),
                                            (FunctionalArea:  $.OrderCapitalExpediture) if $.OrderCapitalExpediture != null
                                        }
                                    })
                            )
                        }
                )
            }
        }
    })
}


[
  {
    "JournalHeader": {
      "InvoiceVoucher": "INV-987654",
      "OrderNumber": "ORD-5678",
      "OrderType": "ORDER",
      "AccountCode": "123456",
      "TransactionCategory": "MEMO",
      "DocumentDate": "2025-12-10",
      "PostingDate": "2025-12-10",
      "Invoice": "INVREF00987654321234567890",
      "CreatedBy": "JaneAdmin",
      "CategoryCode": "PO/INVOICE",
      "Terms": "45",
      "FinancialVendorCode": "VEND002",
      "OrderCapitalExpediture": "789"
    },
    "JournalItems": [
      {
        "Amount": "200.00",
        "Currency": "USD",
        "OrderLine": "OL1001",
        "GLExpenditure": "EXP01",              // prepaid (matches sap_invoice_prepaid)
        "CreditDebitSequence": "1",
        "PartNumberCategory": "ROT",
        "FixedAssetNumber": ["FA010", "FA011"],
        "FixedAssetCount": 2,
        "FinancialLocation": "03",
        "LocationCode": "00",
        "OrderCapitalExpediture": "789"
      },
      {
        "Amount": "-100.00",
        "Currency": "USD",
        "OrderLine": "OL1002",
        "GLExpenditure": "EXP02",              // Not prepaid
        "CreditDebitSequence": "2",
        "PartNumberCategory": "NON-ROT",
        "FixedAssetNumber": ["FA012"],
        "FixedAssetCount": 1,
        "FinancialLocation": "05",
        "LocationCode": "01",
        "OrderCapitalExpediture": null
      },
      {
        "Amount": "75.50",
        "Currency": "EUR",
        "OrderLine": "OL1003",
        "GLExpenditure": "EXP01",              // prepaid
        "CreditDebitSequence": "3",
        "PartNumberCategory": "NON-ROT",
        "FixedAssetNumber": ["FA013"],
        "FixedAssetCount": 1,
        "FinancialLocation": "08",
        "LocationCode": "00",
        "OrderCapitalExpediture": "790"
      },
      {
        "Amount": "-50.50",
        "Currency": "EUR",
        "OrderLine": "OL1004",
        "GLExpenditure": "EXP03",              // Not prepaid
        "CreditDebitSequence": "4",
        "PartNumberCategory": "ROT_ENG",
        "FixedAssetNumber": ["FA014"],
        "FixedAssetCount": 1,
        "FinancialLocation": "08",
        "LocationCode": "02",
        "OrderCapitalExpediture": "791"
      }
    ]
  }
]
