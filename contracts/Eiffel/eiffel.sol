// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "hardhat/console.sol";
// TODO delete all 'console.log' commands

enum Side { BID /*0*/, ASK /*1*/ }

type Prc is int256;
function l(Prc a, Prc b) pure returns (bool)
{
    return Prc.unwrap(a) < Prc.unwrap(b);
}
function le(Prc a, Prc b) pure returns (bool)
{
    return Prc.unwrap(a) <= Prc.unwrap(b);
}
function g(Prc a, Prc b) pure returns (bool)
{
    return Prc.unwrap(a) > Prc.unwrap(b);
}
function ge(Prc a, Prc b) pure returns (bool)
{
    return Prc.unwrap(a) >= Prc.unwrap(b);
}
function eq(Prc a, Prc b) pure returns (bool)
{
    return Prc.unwrap(a) == Prc.unwrap(b);
}
function ne(Prc a, Prc b) pure returns (bool)
{
    return Prc.unwrap(a) != Prc.unwrap(b);
}

type Qty is uint256;

// TODO rename to "Fill"?
struct MatchedOrder
{
    Side restingSide;
    address aggressor;
    address rester;
    Prc prc;
    Qty qty;
}

struct Order
{
    address account;
    Prc prc;
    Qty qty;
}

struct OrderLevel
{
    Side side;
    Prc prc;
    Order[] orders;
    uint256 topOrderInd;
}

function CopyStorageLevel(OrderLevel storage target, OrderLevel storage source)
{
    target.side = source.side;
    target.prc = source.prc;
    delete target.orders;
    // TODO ensure that after deleting orders, we can still push to it.
    for (uint i = 0; i < source.orders.length; ++i)
    {
        target.orders.push(source.orders[i]);
    }
    target.topOrderInd = source.topOrderInd;
}

function CopyLevel(OrderLevel storage target, OrderLevel memory source)
{
    assert(source.orders.length == 1);
    target.side = source.side;
    target.prc = source.prc;
    delete target.orders;
    // TODO ensure that after deleting orders, we can still push to it.
    for (uint i = 0; i < source.orders.length; ++i)
    {
        target.orders.push(source.orders[i]);
    }
    target.topOrderInd = source.topOrderInd;
}

function HasOrders(OrderLevel storage orderLevel) view returns (bool)
{
    return orderLevel.topOrderInd < orderLevel.orders.length;
}

function AddOrder(OrderLevel storage orderLevel, address account, Prc prc, Qty qty)
{
    orderLevel.orders.push(Order(account, prc, qty));
}

function AddMemoryOrder(OrderLevel memory orderLevel, address account, Prc prc, Qty qty) pure
{
    orderLevel.orders = new Order[](1);
    orderLevel.orders[0] = Order(account, prc, qty);
}

function CanMatchAggressor(OrderLevel storage orderLevel, Prc aggressorPrc) view returns (bool)
{
    if (!HasOrders(orderLevel))
        return false;
    return orderLevel.side == Side.BID ? le(aggressorPrc, orderLevel.prc) : ge(aggressorPrc, orderLevel.prc);
}

// incoming aggressing orders, need to match resting orders and clear resting
// returns the qty remaining that was not able to match against resters
// TODO try changing 'MatchedOrder[] memory' to 'MatchedOrder[] storage'
function MatchAggressor(MatchedOrder[] storage matchedOrders, OrderLevel storage orderLevel, Order memory order) returns (Qty)
{
    assert(orderLevel.side == Side.BID ? le(order.prc, orderLevel.prc) : ge(order.prc, orderLevel.prc));
    assert(HasOrders(orderLevel));
    Qty qtyRemaining = order.qty;
    while (Qty.unwrap(qtyRemaining) > 0 && HasOrders(orderLevel))
    {
        Order storage topOrder = orderLevel.orders[orderLevel.topOrderInd];
        if (Qty.unwrap(qtyRemaining) >= Qty.unwrap(topOrder.qty))
        {
            matchedOrders.push(MatchedOrder(orderLevel.side, order.account, topOrder.account, topOrder.prc, topOrder.qty));
            qtyRemaining = Qty.wrap(Qty.unwrap(qtyRemaining) - Qty.unwrap(topOrder.qty));
            topOrder.qty = Qty.wrap(0);
            ++orderLevel.topOrderInd;
        }
        else
        {
            matchedOrders.push(MatchedOrder(orderLevel.side, order.account, topOrder.account, topOrder.prc, qtyRemaining));
            topOrder.qty = Qty.wrap(Qty.unwrap(topOrder.qty) - Qty.unwrap(qtyRemaining));
            qtyRemaining = Qty.wrap(0);
        }
    }
    return qtyRemaining;
}

function GetTotalQty(OrderLevel storage orderLevel) view returns (Qty)
{
    Qty totalQty = Qty.wrap(0);
    for (uint256 i = orderLevel.topOrderInd; i < orderLevel.orders.length; ++i)
    {
        totalQty = Qty.wrap(Qty.unwrap(totalQty) + Qty.unwrap(orderLevel.orders[i].qty));
    }
    return totalQty;
}

struct MarketSide
{
    OrderLevel level1;
    OrderLevel level2;
}

// A resting order can be added if the price is equal or more aggressive than the least aggressive price on the MarketSide
function CanAddRestingOrder(MarketSide storage marketSide, Prc prc) view returns (bool)
{
    assert(marketSide.level1.side == marketSide.level2.side);
    Side side = marketSide.level1.side;
    if (!HasOrders(marketSide.level1) || !HasOrders(marketSide.level2))
        return true;
    return side == Side.BID ? ge(prc, marketSide.level2.prc) : le(prc, marketSide.level2.prc);
}

function AddRestingOrder(MarketSide storage marketSide, OrderLevel[] storage clearedOrderLevels, address account, Prc prc, Qty qty)
{
    assert(CanAddRestingOrder(marketSide, prc));
    assert(clearedOrderLevels.length == 0);
    Side side = marketSide.level1.side;
    OrderLevel storage level1 = marketSide.level1;
    OrderLevel storage level2 = marketSide.level2;
    OrderLevel memory potentialNewOrderLevel;
    potentialNewOrderLevel.side = level1.side;
    potentialNewOrderLevel.prc = prc;
    AddMemoryOrder(potentialNewOrderLevel, account, prc, qty);
    potentialNewOrderLevel.topOrderInd = 0;

    // level1 is empty, a resting order will go there automatically
    if (!HasOrders(level1))
    {
        CopyLevel(level1, potentialNewOrderLevel);
    }
    else if (side == Side.BID)
    {
        if (g(prc, level1.prc))
        {
            if (HasOrders(level2))
            {
                clearedOrderLevels.push(level2);
            }
            CopyStorageLevel(level2, level1);
            CopyLevel(level1, potentialNewOrderLevel);
        }
        else if (eq(prc, level1.prc))
        {
            AddOrder(level1, account, prc, qty);
        }
        else if (!HasOrders(level2))
        {
            CopyLevel(level2, potentialNewOrderLevel);
        }
        else if (g(prc, level2.prc))
        {
            clearedOrderLevels.push(level2);
            CopyLevel(level2, potentialNewOrderLevel);
        }
        else if (eq(prc, level2.prc))
        {
            AddOrder(level2, account, prc, qty);
        }
        else
        {
            assert(false);
        }
    }
    else
    {
        if (l(prc, level1.prc))
        {
            if (HasOrders(level2))
            {
                clearedOrderLevels.push(level2);
            }
            CopyStorageLevel(level2, level1);
            CopyLevel(level1, potentialNewOrderLevel);
        }
        else if (eq(prc, level1.prc))
        {
            AddOrder(level1, account, prc, qty);
        }
        else if (!HasOrders(level2))
        {
            CopyLevel(level2, potentialNewOrderLevel);
        }
        else if (l(prc, level2.prc))
        {
            clearedOrderLevels.push(level2);
            CopyLevel(level2, potentialNewOrderLevel);
        }
        else if (eq(prc, level2.prc))
        {
            AddOrder(level2, account, prc, qty);
        }
        else
        {
            assert(false);
        }
    }
}

function CanMatchOrder(MarketSide storage marketSide, Prc aggressorPrc) view returns (bool)
{
    return CanMatchAggressor(marketSide.level1, aggressorPrc);
}

// returns the qty remaining that was not able to match against resters
function MatchAggressor(MarketSide storage marketSide, MatchedOrder[] storage matchedOrders, address account, Prc prc, Qty qty) returns (Qty)
{
    assert(CanMatchOrder(marketSide, prc));
    Order memory aggressingOrder = Order(account, prc, qty);
    uint prevNumMatchedOrders = matchedOrders.length;
    Qty qtyRemaining = MatchAggressor(matchedOrders, marketSide.level1, aggressingOrder);
    assert(matchedOrders.length > prevNumMatchedOrders);
    aggressingOrder.qty = qtyRemaining;

    if (Qty.unwrap(qtyRemaining) > 0 && CanMatchAggressor(marketSide.level2, prc))
    {
        prevNumMatchedOrders = matchedOrders.length;
        qtyRemaining = MatchAggressor(matchedOrders, marketSide.level2, aggressingOrder);
        assert(matchedOrders.length > prevNumMatchedOrders);
    }

    return qtyRemaining;
}

function GetTotalQty(MarketSide storage marketSide) view returns (Qty)
{
    return Qty.wrap(Qty.unwrap(GetTotalQty(marketSide.level1)) + Qty.unwrap(GetTotalQty(marketSide.level2)));
}

contract Market
{
    event NewOrder(Side side, address account, Prc prc, Qty qty);
    event OrderMatch(Side restingSide, address aggressor, address rester, Prc prc, Qty qty);
    event OrderLevelClear(Side side, Prc prc);

    address constant public _escrowAddress = 0xC3d33C9D05533a17A23175633a091Fe00Fd9F101;

    constructor()
    {
        _bids.level1.side = Side.BID;
        _bids.level2.side = Side.BID;
        _asks.level1.side = Side.ASK;
        _asks.level2.side = Side.ASK;
    }

    // Returns true if the order can be placed (i.e. aggress) and false if it cannot
    // Order is treated as a FOK order, i.e. will not rest on book.
    function AddMarketOrder(Side orderSide, Qty qty) public returns (bool)
    {
        MarketSide storage orderMarketSide = orderSide == Side.BID ? _bids : _asks;
        Qty currentOrderMarketSideTotalQty = GetTotalQty(orderMarketSide);

        MarketSide storage oppositeMarketSide = orderSide == Side.BID ? _asks : _bids;
        Prc oppositeLeastAggressivePrc = orderSide == Side.BID ? Prc.wrap(type(int256).max) : Prc.wrap(type(int256).min); // TODO change int256 -> Prc for stability
        if (CanMatchOrder(oppositeMarketSide, oppositeLeastAggressivePrc))
        {
            Qty oppositeMarketQty = GetTotalQty(oppositeMarketSide);
            qty = Qty.unwrap(qty) <= Qty.unwrap(oppositeMarketQty) ? qty : oppositeMarketQty;
            bool result = AddLimitOrder(orderSide, oppositeLeastAggressivePrc, qty);
            assert(result);
            assert(Qty.unwrap(GetTotalQty(orderMarketSide)) == Qty.unwrap(currentOrderMarketSideTotalQty)); // order side book should not have changed from FOK order
            return true;
        }
        return false;
    }

    // Returns true if the order can be placed (i.e. rest on the book or aggress) and false if it cannot (i.e. is too deep of a level)
    function AddLimitOrder(Side orderSide, Prc prc, Qty qty) public returns (bool)
    {
        require(Qty.unwrap(qty) > 0);
        // TODO lots of potential copies in this function's call stack. flesh them out.

        MarketSide storage orderMarketSide = orderSide == Side.BID ? _bids : _asks;
        MarketSide storage oppositeMarketSide = orderSide == Side.BID ? _asks : _bids;
        if (CanMatchOrder(oppositeMarketSide, prc) || CanAddRestingOrder(orderMarketSide, prc))
        {
            emit NewOrder(orderSide, msg.sender, prc, qty);
        }
        else
        {
            return false;
        }

        Qty remainingQty = qty;
        if (CanMatchOrder(oppositeMarketSide, prc))
        {
            uint prevNumMatchedOrders = _allMatchedOrders.length;
            remainingQty = MatchAggressor(oppositeMarketSide, _allMatchedOrders, msg.sender, prc, qty);
            assert(_allMatchedOrders.length > prevNumMatchedOrders);
            Qty totalMatchedQty = Qty.wrap(0);
            for (uint i = prevNumMatchedOrders; i < _allMatchedOrders.length; ++i)
            {
                totalMatchedQty = Qty.wrap(Qty.unwrap(totalMatchedQty) + Qty.unwrap(_allMatchedOrders[i].qty));
                emit OrderMatch(_allMatchedOrders[i].restingSide, _allMatchedOrders[i].aggressor, _allMatchedOrders[i].rester, _allMatchedOrders[i].prc, _allMatchedOrders[i].qty);
            }
            assert(Qty.unwrap(totalMatchedQty) > 0 && Qty.unwrap(totalMatchedQty) <= Qty.unwrap(qty));
            assert(Qty.unwrap(remainingQty) == Qty.unwrap(qty) - Qty.unwrap(totalMatchedQty));
            if (Qty.unwrap(remainingQty) == 0)
            {
                return true;
            }
        }

        assert(CanAddRestingOrder(orderMarketSide, prc));
        assert(_clearedOrderLevels.length == 0);
        AddRestingOrder(orderMarketSide, _clearedOrderLevels, msg.sender, prc, remainingQty);
        for (uint256 i = 0; i < _clearedOrderLevels.length; ++i)
        {
            emit OrderLevelClear(orderSide, _clearedOrderLevels[i].prc);
        }
        delete _clearedOrderLevels;
        return true;
    }

    function GetMarketQty() public view returns (Qty)
    {
        return Qty.wrap(Qty.unwrap(GetTotalQty(_bids)) + Qty.unwrap(GetTotalQty(_asks)));
    }

    function GetMarketInfo(Side side, uint level) public view returns (Qty, Prc)
    {
        assert(level == 1 || level == 2);
        MarketSide storage marketSide = side == Side.BID ? _bids : _asks;
        OrderLevel storage orderLevel = level == 1 ? marketSide.level1 : marketSide.level2;
        return (GetTotalQty(orderLevel), orderLevel.prc);
    }

    function GetTopOrder(Side side) public view returns (address, Prc, Qty)
    {
        OrderLevel storage orderLevel = side == Side.BID ? _bids.level1 : _asks.level1;
        Order storage topOrder = orderLevel.orders[orderLevel.topOrderInd];
        return (topOrder.account, topOrder.prc, topOrder.qty);
    }

    MarketSide private _bids;
    MarketSide private _asks;
    MatchedOrder[] private _allMatchedOrders;

    // temp variables to use only during function calls
    OrderLevel[] private _clearedOrderLevels;
}
