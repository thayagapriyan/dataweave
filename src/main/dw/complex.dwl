%dw 2.0 
output application/xml
import * from dw::core::Arrays
import mergeWith from dw::core::Objects
import last from dw::core::Strings
ns ns0 http://sap.com/xi/SAPSCORE/SFIN
var pnCategory=read(Mule::p('fixedAssetPnCategory'),'application/json')
fun sendSingleCreditorItem(items,orderType)=do {    
    var CreditorItem=((items partition(item) -> if(orderType=="MEMO")
    (item.Amount contains "-") else !(item.Amount contains "-")).failure) reduce ((item,accumulator) -> {"Amount": (item.Amount + accumulator.Amount )}  ++ ((item - "Amount") mergeWith (accumulator -"Amount")))  
    var Item=((items partition(item) -> if(orderType=="MEMO")
    (item.Amount contains "-") else !(item.Amount contains "-")).success) 
    ---
    Item + CreditorItem
}
fun sendPrepaidItems(items,orderType)=do {
	var g=items groupBy ((item, index) -> (  item.CreditDebitSequence)) mapObject ((value, key, index) -> {(if(value.GLExpenditure contains Mule::p('sap.invoice.prepaid')) "prepaid" else "notprepaid"): value})
    var j=(g.*prepaid) flatMap {($ map {(if(orderType != "MEMO") (if ($.GLExpenditure contains  Mule::p('sap.invoice.prepaid')) "item" else "creditor") else ( if (($.GLExpenditure contains  Mule::p('sap.invoice.prepaid'))) "creditor" else "item")): $})} 
    var k=(g.*notprepaid) flatMap {($ map {(if(orderType != "MEMO") (if ($.Amount contains "-") "creditor" else "item") else ( if($.Amount contains "-") "item" else "creditor")) : $ })} 
    ---
    {
    item: (j.item default [] ) ++ (k.item default []),
    creditor: ((j.creditor default [] ) ++ (k.creditor default [])) reduce ((item,accumulator) -> {"Amount": (item.Amount + accumulator.Amount )}  ++ ((item - "Amount") mergeWith (accumulator -"Amount")))
    }
}
fun calcPennyDiff(amount,fixedAssetCount,index) = if((amount mod fixedAssetCount) != 0 and (fixedAssetCount-1) == index)
    ((((amount/fixedAssetCount) as String {format: "#.##", roundMode : "FLOOR"} as Number ) +
    (amount - (((amount/fixedAssetCount) as String {format: "#.##", roundMode : "FLOOR"} as Number ) * fixedAssetCount) )
    ) as String {format: "#.##", roundMode : "FLOOR"} as Number )
   else ((amount/fixedAssetCount) as String {format: "#.##", roundMode : "FLOOR"} as Number )
---
ns0#JournalEntryBulkCreateRequest: {
        MessageHeader: {
            ID: vars.correlationId,
            CreationDateTime: (now() as String {format: "yyyy-MM-dd'T'hh:mm:ss.SSS'Z'"})
        },
        (payload default [] map using(header=$.JournalHeader,orderCategory=$.JournalHeader.TransactionCategory,companyCodeSize=sizeOf($.JournalHeader.AccountCode))  {
            JournalEntryCreateRequest:{
                MessageHeader:{
                    ID: $.JournalHeader.InvoiceVoucher,
                    CreationDateTime: (now() as String {format: "yyyy-MM-dd'T'hh:mm:ss.SSS'Z'"})
                },
                JournalEntry:{
                    OriginalReferenceDocumentType: Mule::p('sap.originalReferenceDocumentType'),
                    BusinessTransactionType: Mule::p('sap.businessTransactionType'),
                    AccountingDocumentType: Mule::p('sap.accountingDocumentType.invoice'),                   
                    DocumentHeaderText: ($.JournalHeader.OrderNumber default "") ++ "|" ++  ($.JournalHeader.OrderType default ""),
                    CreatedByUser: Mule::p('sap.createdByUser'),
                    CompanyCode: $.JournalHeader.AccountCode,
                    DocumentDate: $.JournalHeader.DocumentDate,
                    PostingDate: if(!isEmpty($.JournalHeader.PostingDate))($.JournalHeader.PostingDate) else ((now() >> "PST") as Date),
                    Reference1InDocumentHeader: $.JournalHeader.Invoice last 20,
					Reference2InDocumentHeader: ($.JournalHeader.CreatedBy default "") ++ "|" ++ ($.JournalHeader.TransactionCategory default ""),
					(if($.JournalItems.GLExpenditure contains Mule::p('sap.invoice.prepaid')) 
						(do {
							var r=sendPrepaidItems($.JournalItems,orderCategory).creditor
							---
							(sendPrepaidItems($.JournalItems,orderCategory).item map {(Item: $.FixedAssetNumber map ((item,index) -> {
								ReferenceDocumentItem: increment(),
								GLAccount: if($.GLExpenditure != Mule::p('sap.invoice.prepaid') and (pnCategory.serialized contains ($.PartNumberCategory)) and !isEmpty($.FixedAssetCount)) p('sap.invoice.faGLAccount') else if($.GLExpenditure != Mule::p('sap.invoice.prepaid') and $.PartNumberCategory == "ROT" and header.CategoryCode == "PO/INVOICE" and isEmpty($.FixedAssetCount)) p('sap.invoice.glAccount') else $.GLExpenditure,
								AmountInTransactionCurrency @(currencyCode: $.Currency): calcPennyDiff($.Amount,$.FixedAssetCount default 1, index),
								DocumentItemText: ($.OrderLine default "") ++ "|" ++ ($.PartNumberCategory default ""),
								AccountAssignment: {
                            	(ProfitCenter: p('sap.profitCenter')) if ($.LocationCode == "00"),			    
								PartnerSegment:"A0" ++ header.Terms,
								(if($.GLExpenditure != Mule::p('sap.invoice.prepaid') and $.PartNumberCategory == "ROT" and header.CategoryCode == "PO/INVOICE" and isEmpty($.FixedAssetCount)) 
									(CostCenter:p('sap.invoice.faCostCenter')) else if ($.LocationCode != "00")
								    (CostCenter: (header.AccountCode[(companyCodeSize-2) to (companyCodeSize-1)] default "") ++ "" ++ ($.FinancialLocation default "") ++ "" ++ ($.LocationCode default "")) else null),
								(MasterFixedAsset: item) if(
									($.GLExpenditure != Mule::p('sap.invoice.prepaid')) and 
									(pnCategory.serialized contains ($.PartNumberCategory)) and 
										($.PartNumberCategory != "ROT_ENG") and 
										!isEmpty($.FixedAssetCount)
								),
								(FixedAsset: p('sap.fixedasset.assetdata.item.subnumber')) if( 
									($.GLExpenditure != Mule::p('sap.invoice.prepaid')) and 
									(pnCategory.serialized contains ($.PartNumberCategory)) and 
									($.PartNumberCategory != "ROT_ENG")
								),
								(FunctionalArea:  $.OrderCapitalExpediture) if $.OrderCapitalExpediture != null
								}								
							}))}) ++ ([{"CreditorItem": {
								ReferenceDocumentItem: 1,
								Creditor: header.FinancialVendorCode,
								AmountInTransactionCurrency @(currencyCode: r.Currency): r.Amount
							}}])
							
						}) else (sendSingleCreditorItem($.JournalItems,orderCategory) map {
                         (if ($.Amount contains("-")) ( if(orderCategory =="MEMO") (Item: $.FixedAssetNumber map ((item,index) -> {
                            ReferenceDocumentItem: increment(),
                            GLAccount: if((pnCategory.serialized contains ($.PartNumberCategory)) and ($.PartNumberCategory != "ROT_ENG") and !isEmpty($.FixedAssetCount)) p('sap.invoice.faGLAccount') else if($.PartNumberCategory == "ROT" and header.CategoryCode == "PO/INVOICE" and isEmpty($.FixedAssetCount)) p('sap.invoice.glAccount') else $.GLExpenditure,
                            AmountInTransactionCurrency @(currencyCode: $.Currency): calcPennyDiff($.Amount,$.FixedAssetCount default 1, index),
                            DocumentItemText: ($.OrderLine default "") ++ "|" ++ ($.PartNumberCategory default ""),
                            AccountAssignment: {
                            	(ProfitCenter: p('sap.profitCenter')) if ($.LocationCode == "00"),			    
								PartnerSegment:"A0" ++ header.Terms,
								(if($.PartNumberCategory == "ROT" and header.CategoryCode == "PO/INVOICE" 
									and isEmpty($.FixedAssetCount)
								) 
									(CostCenter:p('sap.invoice.faCostCenter')) else if ($.LocationCode != "00")
								    (CostCenter: (header.AccountCode[(companyCodeSize-2) to (companyCodeSize-1)] default "") ++ "" ++ ($.FinancialLocation default "") ++ "" ++ ($.LocationCode default "")) else null),
								(MasterFixedAsset: item) if(
									(pnCategory.serialized contains 
									($.PartNumberCategory)) 
									and ($.PartNumberCategory != "ROT_ENG")
								 and !isEmpty($.FixedAssetCount)
								 ),
								(FixedAsset: p('sap.fixedasset.assetdata.item.subnumber')) 
								if( (pnCategory.serialized contains ($.PartNumberCategory)) and ($.PartNumberCategory != "ROT_ENG") ),
								(FunctionalArea:  $.OrderCapitalExpediture) if $.OrderCapitalExpediture != null
								}
                     })) else CreditorItem:{
                            ReferenceDocumentItem: increment(),
                            Creditor: header.FinancialVendorCode,
                            AmountInTransactionCurrency @(currencyCode: $.Currency): ($.Amount as Number {format: "#.##", roundMode : "CEILING"})
                        }) else if(orderCategory =="MEMO")(CreditorItem:{
                            ReferenceDocumentItem: increment(),
                            Creditor: header.FinancialVendorCode,
                            AmountInTransactionCurrency @(currencyCode: $.Currency): ($.Amount as Number {format: "#.##", roundMode : "CEILING"})
                        }) else (Item: $.FixedAssetNumber map ((item,index) ->  {
                            ReferenceDocumentItem: increment(),
                            GLAccount: if((pnCategory.serialized contains ($.PartNumberCategory)) and ($.PartNumberCategory != "ROT_ENG") and !isEmpty($.FixedAssetCount)) p('sap.invoice.faGLAccount') else if(orderCategory == "ORDER" and $.PartNumberCategory == "ROT" and header.CategoryCode == "PO/INVOICE" and isEmpty($.FixedAssetCount)) p('sap.invoice.glAccount') else $.GLExpenditure,
                            AmountInTransactionCurrency @(currencyCode: $.Currency): calcPennyDiff($.Amount,$.FixedAssetCount default 1, index),
                            DocumentItemText: ($.OrderLine default "") ++ "|" ++ ($.PartNumberCategory default ""),
                            AccountAssignment: {
                            	(ProfitCenter: p('sap.profitCenter')) if ($.LocationCode == "00"),
                            	PartnerSegment:"A0" ++ header.Terms,
                            	(if(orderCategory == "ORDER" and $.PartNumberCategory == "ROT" and header.CategoryCode == "PO/INVOICE" and isEmpty($.FixedAssetCount)) 
									(CostCenter:p('sap.invoice.faCostCenter')) else if ($.LocationCode != "00")
								    (CostCenter: (header.AccountCode[(companyCodeSize-2) to (companyCodeSize-1)] default "") ++ "" ++ ($.FinancialLocation default "") ++ "" ++ ($.LocationCode default "")) else null),
								(MasterFixedAsset: item) if(
									(pnCategory.serialized contains ($.PartNumberCategory)) and 
									($.PartNumberCategory != "ROT_ENG") and 
									!isEmpty($.FixedAssetCount)
								),	
								(FixedAsset: p('sap.fixedasset.assetdata.item.subnumber')) if( 
									(pnCategory.serialized contains ($.PartNumberCategory)) and 
									($.PartNumberCategory != "ROT_ENG")
								),						    
								(FunctionalArea:  $.OrderCapitalExpediture) if $.OrderCapitalExpediture != null
								}
                     })))}))
            }
            }
        })
}

[{
  "JournalHeader": {
    "AccountCode": "0020",
    "DocumentDate": "2022-11-18",
    "PostingDate": "2022-11-18",
    "VendorCode": "123456",
    "FinancialVendorCode": "100000",
    "JournalNumber": null,
    "CreatedBy": "G4DEV",
    "SourceSystem": "TRAX",
    "Invoice": "IN133445",
    "InvoiceVoucher": "589",
    "OrderType": "INVOICE",
    "OrderNumber": "133445",
    "Source": null,
    "TransactionIdentifier": null,
    "TransactionCategory": "ORDER",
    "Terms": "06"
  },
  "JournalItems": [
    {
      "Amount": "100",
      "OrderLine": "1",
      "Description": null,
      "LocationCode": "53008",
      "FinancialLocation": "LAS",
      "Currency": "USD",
      "OrderCapitalExpediture": "1752311004",
      "GLExpenditure": "70555001",
      "PartNumber": null,
      "PartNumberCategory": "ROT",
      "TransactionType": null,
      "FixedAssetNumber": [
        "31355",
        "31356"
      ],
      "FixedAssetCount": "2"
    },
    {
      "Amount": "-100",
      "OrderLine": "1",
      "Description": null,
      "LocationCode": "00",
      "FinancialLocation": "LAS",
      "Currency": "USD",
      "OrderCapitalExpediture": "1752311004",
      "GLExpenditure": "20140100",
      "PartNumber": null,
      "PartNumberCategory": "ROT",
      "TransactionType": null,
      "FixedAssetNumber": [
        "31355",
        "31356"
      ],
      "FixedAssetCount": "2"
    },
    {
      "Amount": "200",
      "OrderLine": "2",
      "Description": null,
      "LocationCode": "53008",
      "FinancialLocation": "LAS",
      "Currency": "USD",
      "OrderCapitalExpediture": null,
      "GLExpenditure": "70555001",
      "PartNumber": null,
      "PartNumberCategory": "EXP",
      "TransactionType": null,
      "FixedAssetNumber": [
        ""
      ],
      "FixedAssetCount": null
    },
    {
      "Amount": "-200",
      "OrderLine": "2",
      "Description": null,
      "LocationCode": "00",
      "FinancialLocation": "LAS",
      "Currency": "USD",
      "OrderCapitalExpediture": "1752311004",
      "GLExpenditure": "20140100",
      "PartNumber": null,
      "PartNumberCategory": "EXP",
      "TransactionType": null,
      "FixedAssetNumber": [
        ""
      ],
      "FixedAssetCount": null
    }
  ],
  "batchCorrelationId": "TRXca8183c120d846ffa9665d85a65cdf2f",
  "batchDate": "2022-11-18T07:45:00.601Z",
  "sourceSystem": "TRAX",
  "invoiceCount": 1
}]
