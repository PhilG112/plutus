@{%
const marlowe = require('./src/Marlowe/Holes')
const semantics = require('./src/Marlowe/Semantics')
const bigInteger = require('./src/Data/BigInteger');

const moo = require("moo");

const lexer = moo.compile({
        WS: /[ \t]+/,
        number: /0|-?[1-9][0-9]*/,
        string: {match: /"(?:\\["\\]|[^\n"\\])*"/, value: x => x.slice(1, -1)},
        ratio: '%',
        comma: ',',
        lparen: '(',
        rparen: ')',
        lsquare: '[',
        rsquare: ']',
        hole: /\?[a-zA-Z0-9_-]+/,
        CONSTRUCTORS: {
            match: /[A-Z][A-Za-z]+/, type: moo.keywords({
                CONTRACT: ['Close', 'Pay', 'If', 'When', 'Let', 'Assert'],
                OBSERVATION: [
                    'AndObs',
                    'OrObs',
                    'NotObs',
                    'ChoseSomething',
                    'ValueGE',
                    'ValueGT',
                    'ValueLT',
                    'ValueLE',
                    'ValueEQ',
                    'TrueObs',
                    'FalseObs',
                ],
                VALUE: [
                    'AvailableMoney',
                    'Constant',
                    'NegValue',
                    'AddValue',
                    'SubValue',
                    'MulValue',
                    'Scale',
                    'ChoiceValue',
                    'SlotIntervalStart',
                    'SlotIntervalEnd',
                    'UseValue',
                    'Cond'
                ],
                ACCOUNT_ID: ['AccountId'],
                TOKEN: ['Token'],
                PAYEE: ['Account', 'Party'],
                PARTY: ['PK', 'Role'],
                BOUND: ['Bound'],
                VALUE_ID: ['ValueId'],
                CASE: ['Case'],
                ACTION: ['Deposit', 'Choice', 'Notify'],
                CHOICE_ID: ['ChoiceId'],
            })
        },
        NL: { match: /\n/, lineBreaks: true },
        myError: {match: /[\$?`]/, error: true},
});

%}

# Pass your lexer object using the @lexer option:
@lexer lexer

main -> ws:* topContract ws:* {%([,contract,]) => contract%}

ws -> %WS | %NL

# At least one whitespace
someWS -> ws:+

# none or some whitespace
manyWS -> ws:*

lparen -> %lparen  manyWS {% ([t,]) => t %}

rparen ->  manyWS %rparen {% ([,t]) => t %}

lsquare -> %lsquare manyWS

rsquare ->  manyWS %rsquare

hole -> %hole {% ([hole]) => marlowe.mkHole(hole.value.substring(1))({startLineNumber: hole.line, startColumn: hole.col, endLineNumber: hole.line, endColumn: hole.col + hole.value.length}) %}

number
   -> %number {% ([n]) => bigInteger.fromInt(n.value) %}
    | lparen %number rparen {% ([,n,]) => bigInteger.fromInt(n.value) %}

timeout
   -> %number {% ([n]) => marlowe.mkTimeout(n.value)({startLineNumber: n.line, startColumn: n.col, endLineNumber: n.line, endColumn: n.col + n.value.toString().length}) %}
    | lparen %number rparen {% ([start,n,end]) => marlowe.mkTimeout(n.value)({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}

string
   -> %string {% ([s]) => s.value %}

topContract
   -> hole {% ([hole]) => hole %}
    | "Close" {% ([{line, col}]) => marlowe.Term.create(marlowe.Close.value)({startLineNumber: line, startColumn: col, endLineNumber: line, endColumn: col + 5}) %}
    | "Pay" someWS accountId someWS payee someWS token someWS value someWS contract {% ([{line, col},,accountId,,payee,,token,,value,,contract]) => marlowe.Term.create(marlowe.Pay.create(accountId)(payee)(token)(value)(contract))({startLineNumber: line, startColumn: col, endLineNumber: marlowe.getRange(contract).endLineNumber, endColumn: marlowe.getRange(contract).endColumn}) %}
    | "If" someWS observation someWS contract someWS contract {% ([{line, col},,observation,,contract1,,contract2]) => marlowe.Term.create(marlowe.If.create(observation)(contract1)(contract2))({startLineNumber: line, startColumn: col, endLineNumber: marlowe.getRange(contract2).endLineNumber, endColumn: marlowe.getRange(contract2).endColumn}) %}
    | "When" someWS lsquare cases:* rsquare someWS timeout someWS contract {% ([{line, col},,,cases,,,timeout,,contract]) => marlowe.Term.create(marlowe.When.create(cases)(timeout)(contract))({startLineNumber: line, startColumn: col, endLineNumber: marlowe.getRange(contract).endLineNumber, endColumn: marlowe.getRange(contract).endColumn}) %}
    | "Let" someWS valueId someWS value someWS contract {% ([{line, col},,valueId,,value,,contract]) => marlowe.Term.create(marlowe.Let.create(valueId)(value)(contract))({startLineNumber: line, startColumn: col, endLineNumber: marlowe.getRange(contract).endLineNumber, endColumn: marlowe.getRange(contract).endColumn}) %}
    | "Assert" someWS observation someWS contract {% ([{line, col},,observation,,contract]) => marlowe.Term.create(marlowe.Assert.create(observation)(contract))({startLineNumber: line, startColumn: col, endLineNumber: marlowe.getRange(contract).endLineNumber, endColumn: marlowe.getRange(contract).endColumn}) %}

cases
   -> hole {% ([hole]) => hole %}
    | case {% id %}
    | manyWS %comma manyWS case {% ([,,,case_]) => case_ %}

case
   -> hole {% ([hole]) => hole %}
    | "Case" someWS action someWS contract {% ([{line, col},,action,,contract]) => marlowe.Term.create(marlowe.Case.create(action)(contract))({startLineNumber: line, startColumn: col, endLineNumber: marlowe.getRange(contract).endLineNumber, endColumn: marlowe.getRange(contract).endColumn}) %}
    | lparen "Case" someWS action someWS contract rparen {% ([start,,,action,,contract,end]) => marlowe.Term.create(marlowe.Case.create(action)(contract))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}

bounds
   -> hole {% ([hole]) => hole %}
    | bound {% id %}
    | manyWS %comma manyWS bound {% ([,,,bound]) => bound %}

bound
   -> hole {% ([hole]) => hole %}
    | "Bound" someWS number someWS number {% ([{line, col},,bottom,,top]) => marlowe.Term.create(marlowe.Bound.create(bottom)(top))({startLineNumber: line, startColumn: col, endLineNumber: top.line, endColumn: top.col + top.value.toString().length}) %}
    | lparen bound rparen {% ([,bound,]) => bound %}

action
   -> hole {% ([hole]) => hole %}
    | lparen "Deposit" someWS accountId someWS party someWS token someWS value rparen {% ([start,{line, col},,accountId,,party,,token,,value,end]) => marlowe.Term.create(marlowe.Deposit.create(accountId)(party)(token)(value))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "Choice" someWS choiceId someWS lsquare bounds:* rsquare rparen {% ([start,{line, col},,choiceId,,,bounds,,end]) => marlowe.Term.create(marlowe.Choice.create(choiceId)(bounds))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "Notify" someWS observation rparen {% ([start,{line, col},,observation,end]) => marlowe.Term.create(marlowe.Notify.create(observation))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}

# Beacause top level contracts don't have parenthesis we need to duplicate the lower-level contracts in order to get the start and end positions
contract
   -> hole {% ([hole]) => hole %}
    | "Close" {% ([{line,col}]) => marlowe.Term.create(marlowe.Close.value)({startLineNumber: line, startColumn: col, endLineNumber: line, endColumn: col + 5}) %}
    | lparen "Pay" someWS accountId someWS payee someWS token someWS value someWS contract rparen {% ([start,{line, col},,accountId,,payee,,token,,value,,contract,end]) => marlowe.Term.create(marlowe.Pay.create(accountId)(payee)(token)(value)(contract))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "If" someWS observation someWS contract someWS contract rparen {% ([start,{line, col},,observation,,contract1,,contract2,end]) => marlowe.Term.create(marlowe.If.create(observation)(contract1)(contract2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "When" someWS lsquare cases:* rsquare someWS timeout someWS contract rparen {% ([start,{line, col},,,cases,,,timeout,,contract,end]) => marlowe.Term.create(marlowe.When.create(cases)(timeout)(contract))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "Let" someWS valueId someWS value someWS contract rparen {% ([start,{line, col},,valueId,,value,,contract,end]) => marlowe.Term.create(marlowe.Let.create(valueId)(value)(contract))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "Assert" someWS observation someWS contract rparen {% ([start,{line, col},,observation,,contract,end]) => marlowe.Term.create(marlowe.Assert.create(observation)(contract))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}

choiceId
   -> lparen %CHOICE_ID someWS string someWS party rparen {% ([,{line,col},,cid,,party,]) => marlowe.ChoiceId.create(cid)(party) %}

# FIXME: There is a difference between the Haskell pretty printer and the purescript parser
valueId
   -> %string {% ([{value,line,col}]) => marlowe.TermWrapper.create(marlowe.ValueId(value))({startLineNumber: line, startColumn: col, endLineNumber: line, endColumn: col + value.length}) %}
# valueId -> lparen %VALUE_ID someWS string rparen

accountId
   -> lparen %ACCOUNT_ID someWS number someWS party rparen {% ([,{line,col},,aid,,party,]) => marlowe.AccountId.create(aid)(party) %}

token
   -> hole {% ([hole]) => hole %}
    | lparen %TOKEN someWS string someWS string rparen {% ([start,{line,col},,a,,b,end]) => marlowe.Term.create(marlowe.Token.create(a)(b))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}

party
   -> hole {% ([hole]) => hole %}
    | lparen "PK" someWS string rparen {% ([start,{line,col},,k,end]) => marlowe.Term.create(marlowe.PK.create(k))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "Role" someWS string rparen {% ([start,{line,col},,k,end]) => marlowe.Term.create(marlowe.Role.create(k))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}

payee
   -> hole {% ([hole]) => hole %}
    | lparen "Account" someWS accountId rparen {% ([start,{line,col},,accountId,end]) => marlowe.Term.create(marlowe.Account.create(accountId))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "Party" someWS party rparen {% ([start,{line,col},,party,end]) => marlowe.Term.create(marlowe.Party.create(party))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}

observation
   -> hole {% ([hole]) => hole %}
    | lparen "AndObs" someWS observation someWS observation rparen {% ([start,{line,col},,o1,,o2,end]) => marlowe.Term.create(marlowe.AndObs.create(o1)(o2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "OrObs" someWS observation someWS observation rparen {% ([start,{line,col},,o1,,o2,end]) => marlowe.Term.create(marlowe.OrObs.create(o1)(o2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "NotObs" someWS observation rparen {% ([start,{line,col},,o1,end]) => marlowe.Term.create(marlowe.NotObs.create(o1))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "ChoseSomething" someWS choiceId rparen {% ([start,{line,col},,choiceId,end]) => marlowe.Term.create(marlowe.ChoseSomething.create(choiceId))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "ValueGE" someWS value someWS value rparen {% ([start,{line,col},,v1,,v2,end]) => marlowe.Term.create(marlowe.ValueGE.create(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "ValueGT" someWS value someWS value rparen {% ([start,{line,col},,v1,,v2,end]) => marlowe.Term.create(marlowe.ValueGT.create(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "ValueLT" someWS value someWS value rparen {% ([start,{line,col},,v1,,v2,end]) => marlowe.Term.create(marlowe.ValueLT.create(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "ValueLE" someWS value someWS value rparen {% ([start,{line,col},,v1,,v2,end]) => marlowe.Term.create(marlowe.ValueLE.create(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | lparen "ValueEQ" someWS value someWS value rparen {% ([start,{line,col},,v1,,v2,end]) => marlowe.Term.create(marlowe.ValueEQ.create(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col}) %}
    | "TrueObs" {% ([{line,col}]) => marlowe.Term.create(marlowe.TrueObs.value)({startLineNumber: line, startColumn: col, endLineNumber: line, endColumn: col + 7}) %}
    | "FalseObs" {% ([{line,col}]) => marlowe.Term.create(marlowe.FalseObs.value)({startLineNumber: line, startColumn: col, endLineNumber: line, endColumn: col + 8}) %}

rational
    -> hole {% ([hole]) => hole %}
    | number manyWS %ratio manyWS number {%([num,,,,denom]) => marlowe.Term.create(semantics.Rational.create(num)(denom))({startLineNumber: num.line, startColumn: num.col, endLineNumber: denom.line, endColumn: denom.col + denom.value.toString().length}) %}

value
   -> hole {% ([hole]) => hole %}
    | lparen "AvailableMoney" someWS accountId someWS token rparen {% ([start,{line,col},,accountId,,token,end]) => marlowe.Term.create(marlowe.AvailableMoney.create(accountId)(token))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | lparen "Constant" someWS number rparen {% ([start,{line,col},,number,end]) => marlowe.Term.create(marlowe.Constant.create(number))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | lparen "NegValue" someWS value rparen {% ([start,{line,col},,value,end]) => marlowe.Term.create(marlowe.NegValue.create(value))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | lparen "AddValue" someWS value someWS value rparen {% ([start,{line,col},,v1,,v2,end]) => marlowe.Term.create(marlowe.AddValue.create(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | lparen "SubValue" someWS value someWS value rparen {% ([start,{line,col},,v1,,v2,end]) => marlowe.Term.create(marlowe.SubValue.create(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | lparen "MulValue" someWS value someWS value rparen {% ([start,{line,col},,v1,,v2,end]) => marlowe.Term.create(marlowe.MulValue.create(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | lparen "Scale" someWS lparen rational rparen someWS value rparen {% ([start,{line,col},,,ratio,,,v,end]) => marlowe.Term.create(marlowe.Scale.create(ratio)(v))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | lparen "ChoiceValue" someWS choiceId rparen {% ([start,{line,col},,choiceId,end]) => marlowe.Term.create(marlowe.ChoiceValue.create(choiceId))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | "SlotIntervalStart" {% ([{line,col}]) => marlowe.Term.create(marlowe.SlotIntervalStart.value)({startLineNumber: line, startColumn: col, endLineNumber: line, endColumn: col + 17}) %}
    | "SlotIntervalEnd" {% ([{line,col}]) => marlowe.Term.create(marlowe.SlotIntervalEnd.value)({startLineNumber: line, startColumn: col, endLineNumber: line, endColumn: col + 15}) %}
    | lparen "UseValue" someWS valueId rparen {% ([start,{line,col},,valueId,end]) => marlowe.Term.create(marlowe.UseValue.create(valueId))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
    | lparen "Cond" someWS observation someWS value someWS value rparen {% ([start,{line,col},,oo,,v1,,v2,end]) => marlowe.Term.create(marlowe.Cond.create(oo)(v1)(v2))({startLineNumber: start.line, startColumn: start.col, endLineNumber: end.line, endColumn: end.col + 1}) %}
