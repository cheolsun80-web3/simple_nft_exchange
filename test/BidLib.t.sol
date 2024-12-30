// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/BidLib.sol";

contract BidLibTest is Test {
    using BidLib for BidLib.Heap;

    // 실제 테스트할 Heap 구조체
    BidLib.Heap private heap;

    // 테스트 시작 전 실행될 초기화 함수
    function setUp() public {
        heap.init(); // 0번 인덱스 dummy 삽입
    }

    //---------------------------------------
    // 기존 테스트 함수
    //---------------------------------------

    function testInsertAndGetMax() public {
        heap.insert(BidLib.Bidder(address(0x123), 1), 10);
        heap.insert(BidLib.Bidder(address(0x456), 2), 20);
        heap.insert(BidLib.Bidder(address(0x789), 3), 15);

        (BidLib.Bidder memory bidder, uint256 price) = heap.getMax();
        assertEq(bidder.bidder, address(0x456));
        assertEq(price, 20);
    }

    function testExtractMax() public {
        heap.insert(BidLib.Bidder(address(0xAAA), 11), 10);
        heap.insert(BidLib.Bidder(address(0xBBB), 22), 30);
        heap.insert(BidLib.Bidder(address(0xCCC), 33), 20);

        (BidLib.Bidder memory maxBidder, uint256 maxPrice) = heap.extractMax();
        assertEq(maxBidder.bidder, address(0xBBB));
        assertEq(maxPrice, 30);

        (BidLib.Bidder memory newMaxBidder, uint256 newMaxPrice) = heap.getMax();
        assertEq(newMaxBidder.bidder, address(0xCCC));
        assertEq(newMaxPrice, 20);

        assertEq(heap.size(), 2);
    }

    function testRemoveAtIndex() public {
        heap.insert(BidLib.Bidder(address(0x111), 1), 100);
        heap.insert(BidLib.Bidder(address(0x222), 2), 50);
        heap.insert(BidLib.Bidder(address(0x333), 3), 70);

        // 두 번째 원소 제거
        heap.removeAtIndex(2);

        // 제거 후 사이즈는 2
        assertEq(heap.size(), 2);

        // 가장 높은 price는 100
        (BidLib.Bidder memory remainingBidder, uint256 remainingPrice) = heap.getMax();
        assertEq(remainingBidder.bidder, address(0x111));
        assertEq(remainingPrice, 100);
    }

    function testGetBidIndexByAddressAndNonce() public {
        heap.insert(BidLib.Bidder(address(0x999), 99), 10);
        heap.insert(BidLib.Bidder(address(0x888), 88), 20);
        heap.insert(BidLib.Bidder(address(0x777), 77), 30);

        uint256 idx = heap.getBidIndexByAddressAndNonce(address(0x888), 88);
        assertGt(idx, 0, "error");

        BidLib.Bid memory b = heap.getBidAtIndex(idx);
        assertEq(b.bidder.bidder, address(0x888));
        assertEq(b.bidder.nonce, 88);
        assertEq(b.price, 20);
    }

    function testHeapViewFunctions() public {
        assertEq(heap.size(), 0);

        heap.insert(BidLib.Bidder(address(0xABC), 1), 100);
        heap.insert(BidLib.Bidder(address(0xDEF), 2), 200);
        assertEq(heap.size(), 2);

        BidLib.Bid[] memory allBids = heap.getHeap();
        assertEq(allBids.length, 2);
        assertEq(allBids[0].price, 200);
        assertEq(allBids[1].price, 100);
    }

    //---------------------------------------
    // 추가 테스트 함수들
    //---------------------------------------

    /**
     * @notice 같은 price를 가진 Bid를 여러 번 삽입해도, size 체크와 getMax()만 정확히 처리되면 정상 동작
     */
    function testInsertSamePrice() public {
        // 각각 100으로 동일 price
        heap.insert(BidLib.Bidder(address(0xA1), 1), 100);
        heap.insert(BidLib.Bidder(address(0xB2), 2), 100);
        heap.insert(BidLib.Bidder(address(0xC3), 3), 100);

        // size는 3이어야 함
        assertEq(heap.size(), 3);

        // 최대값이 100인 것 확인 (동일 price이므로 어떤 address든 100이면 OK)
        (BidLib.Bidder memory bidder, uint256 price) = heap.getMax();
        assertEq(price, 100);
    }

    /**
     * @notice 같은 address라도 nonce가 다르면 서로 다른 Bid
     */
    function testInsertSameAddressDifferentNonce() public {
        address sameBidder = address(0xABC);

        heap.insert(BidLib.Bidder(sameBidder, 1), 10);
        heap.insert(BidLib.Bidder(sameBidder, 2), 20);
        heap.insert(BidLib.Bidder(sameBidder, 3), 15);

        // 최대가격 = 20
        (BidLib.Bidder memory maxBidder, uint256 price) = heap.getMax();
        assertEq(maxBidder.bidder, sameBidder);
        assertEq(maxBidder.nonce, 2);
        assertEq(price, 20);
    }

    /**
     * @notice (address, nonce)가 완전히 동일한 경우를 삽입 ->
     *         라이브러리 자체는 막지 않으므로 중복이 가능. 상위 컨트랙트 단에서 로직 제어 필요.
     *         여기서는 단지 중복 삽입 후 사이즈와 getMax()가 정상 동작하는지만 확인
     */
    function testInsertSameAddressSameNonce() public {
        address sameBidder = address(0xABC);

        heap.insert(BidLib.Bidder(sameBidder, 999), 10);
        heap.insert(BidLib.Bidder(sameBidder, 999), 15); // 중복 (address, nonce)

        // 총 2개
        assertEq(heap.size(), 2);

        // 최대값은 15
        (BidLib.Bidder memory maxBidder, uint256 maxPrice) = heap.getMax();
        assertEq(maxPrice, 15);
        assertEq(maxBidder.bidder, sameBidder);
        assertEq(maxBidder.nonce, 999);
    }

    /**
     * @notice 힙이 비었을 때 extractMax()를 호출하면 revert 없이 (0,0) 반환되는지 확인
     *         removeAtIndex() 등은 require로 막으므로 revert가 발생해야 함
     */
    function testEmptyHeapOperations() public {
        // 초기 사이즈는 0
        assertEq(heap.size(), 0);

        // extractMax() -> (address(0),0) 반환
        (BidLib.Bidder memory emptyBidder, uint256 emptyPrice) = heap.extractMax();
        assertEq(emptyBidder.bidder, address(0));
        assertEq(emptyBidder.nonce, 0);
        assertEq(emptyPrice, 0);

        // removeAtIndex(1) -> "Heap is empty" revert
        vm.expectRevert(bytes("Heap is empty"));
        heap.removeAtIndex(1);
    }

    /**
     * @notice 허용되지 않은 인덱스를 removeAtIndex()로 제거 -> revert 확인
     */
    function testRemoveInvalidIndex() public {
        heap.insert(BidLib.Bidder(address(0xA), 1), 100);

        // 힙 size=1 -> 유효 인덱스는 오직 1
        // 인덱스 0은 dummy, 2 이상은 out of range
        vm.expectRevert(bytes("Invalid index"));
        heap.removeAtIndex(2);

        vm.expectRevert(bytes("Invalid index"));
        heap.removeAtIndex(0);

        // 유효 인덱스 1은 제거 가능
        heap.removeAtIndex(1);
        assertEq(heap.size(), 0);
    }

    /**
     * @notice 루트(인덱스=1) 제거 시, 다른 노드가 루트로 올라온 뒤에도 힙 정렬이 유지되는지 확인
     */
    function testRemoveRootIndex() public {
        heap.insert(BidLib.Bidder(address(0xAAA), 1), 50);
        heap.insert(BidLib.Bidder(address(0xBBB), 2), 100);
        heap.insert(BidLib.Bidder(address(0xCCC), 3), 70);

        // 루트 제거(인덱스=1)는 price=100이 사라진다는 뜻
        heap.removeAtIndex(1);

        // 제거 후 size=2
        assertEq(heap.size(), 2);

        // 최대값이 70인지 확인
        (BidLib.Bidder memory maxBidder, uint256 maxPrice) = heap.getMax();
        assertEq(maxPrice, 70);
        assertEq(maxBidder.bidder, address(0xCCC));
    }

    /**
     * @notice 임의로 여러 개의 price 삽입 후, 전체가 제대로 최대 힙 구조를 유지하는지(단순히 getMax() 연속 호출)
     */
    function testMultipleInsertRandom() public {
        // 무작위 price 삽입
        heap.insert(BidLib.Bidder(address(0x1), 1), 5);
        heap.insert(BidLib.Bidder(address(0x2), 2), 15);
        heap.insert(BidLib.Bidder(address(0x3), 3), 3);
        heap.insert(BidLib.Bidder(address(0x4), 4), 9);
        heap.insert(BidLib.Bidder(address(0x5), 5), 40);
        heap.insert(BidLib.Bidder(address(0x6), 6), 7);

        // 현재 최대값은 40
        (BidLib.Bidder memory bidder1, uint256 price1) = heap.extractMax();
        assertEq(price1, 40);

        // 이제 남은 것 중 최대값은 15
        (BidLib.Bidder memory bidder2, uint256 price2) = heap.extractMax();
        assertEq(price2, 15);

        // 그 다음 최대값은 9
        (BidLib.Bidder memory bidder3, uint256 price3) = heap.extractMax();
        assertEq(price3, 9);

        // 그 다음 7
        (BidLib.Bidder memory bidder4, uint256 price4) = heap.extractMax();
        assertEq(price4, 7);

        // 그 다음 5
        (BidLib.Bidder memory bidder5, uint256 price5) = heap.extractMax();
        assertEq(price5, 5);

        // 마지막 3
        (BidLib.Bidder memory bidder6, uint256 price6) = heap.extractMax();
        assertEq(price6, 3);

        // 이제 힙은 비어 있음
        assertEq(heap.size(), 0);
    }
}
