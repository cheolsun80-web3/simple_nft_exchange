// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library BidLib {
    /**
     * @dev 힙에 저장할 데이터 구조체
     */
    struct Bidder {
        address bidder;
        uint256 nonce;
    }

    struct Bid {
        Bidder bidder;
        uint256 price;
    }

    /**
     * @dev 라이브러리에서 관리할 Heap 구조체
     *      0번 인덱스는 더미(dummy)로 사용하기 위해
     *      Bid 배열을 가지고 있음
     */
    struct Heap {
        Bid[] data; // 인덱스 0은 사용 안 함
    }

    /**
     * @dev 힙을 초기화하면서, 더미 인덱스용 Bid를 삽입
     *      (constructor 대용)
     */
    function init(Heap storage self) internal {
        if (self.data.length == 0) {
            self.data.push(Bid(Bidder(address(0), 0), 0));
        }
    }

    /**
     * @dev 힙 크기 반환 (더미 제외)
     */
    function size(Heap storage self) internal view returns (uint256) {
        if (self.data.length <= 1) {
            return 0;
        }
        return self.data.length - 1;
    }

    /**
     * @dev 힙 전체를 배열로 반환 (디버깅/테스트용)
     *      0번 인덱스는 더미이므로 제외
     */
    function getHeap(Heap storage self) internal view returns (Bid[] memory) {
        uint256 length = self.data.length;
        if (length <= 1) {
            return new Bid[](0);
        }
        Bid[] memory result = new Bid[](length - 1);
        for (uint256 i = 1; i < length; i++) {
            result[i - 1] = self.data[i];
        }
        return result;
    }

    /**
     * @dev 새 Bid 삽입 (Max Heap 유지)
     */
    function insert(Heap storage self, Bidder memory _bidder, uint256 _price) internal {
        if (self.data.length == 0) {
            init(self);
        }

        self.data.push(Bid(_bidder, _price));
        bubbleUp(self, self.data.length - 1);
    }

    /**
     * @dev 힙의 루트(최댓값)를 확인 (삭제 없음)
     */
    function getMax(Heap storage self) internal view returns (Bidder memory, uint256) {
        if (self.data.length <= 1) {
            return (Bidder(address(0), 0), 0);
        }
        return (self.data[1].bidder, self.data[1].price);
    }

    /**
     * @dev 루트(최댓값) 추출 (삭제 O(log n))
     */
    function extractMax(Heap storage self) internal returns (Bidder memory, uint256) {
        uint256 length = self.data.length;
        if (length <= 1) {
            return (Bidder(address(0), 0), 0);
        }

        Bid memory maxBid = self.data[1];

        // 마지막 요소를 루트로 올리고 pop
        self.data[1] = self.data[length - 1];
        self.data.pop();

        if (self.data.length > 1) {
            bubbleDown(self, 1);
        }
        return (maxBid.bidder, maxBid.price);
    }

    /**
     * @dev 특정 인덱스(i) 위치의 원소를 제거 (O(log n))
     *      i가 1~size() 범위 내여야 함 (0번 인덱스는 dummy)
     */
    function removeAtIndex(Heap storage self, uint256 i) internal {
        uint256 length = self.data.length;
        require(length > 1, "Heap is empty");
        require(i > 0 && i < length, "Invalid index");

        // 만약 지우려는 인덱스가 맨 마지막 요소라면 그냥 pop
        if (i == length - 1) {
            self.data.pop();
        } else {
            // 마지막 요소를 현재 인덱스로 복사
            self.data[i] = self.data[length - 1];
            self.data.pop();

            // bubbleUp 또는 bubbleDown 판단
            uint256 parentIndex = i / 2;
            // i가 루트가 아니고, 부모보다 현재 노드 price가 더 크면 bubbleUp
            if (i > 1 && self.data[i].price > self.data[parentIndex].price) {
                bubbleUp(self, i);
            } else {
                // 그 외의 경우 bubbleDown
                bubbleDown(self, i);
            }
        }
    }

    function getBidAtIndex(Heap storage self, uint256 i) internal view returns (Bid memory) {
        require(i > 0 && i < self.data.length, "Invalid index");
        return self.data[i];
    }

    function getBidIndexByAddressAndNonce(Heap storage self, address bidder, uint256 nonce)
        internal
        view
        returns (uint256)
    {
        for (uint256 i = 1; i < self.data.length; i++) {
            if (self.data[i].bidder.bidder == bidder && self.data[i].bidder.nonce == nonce) {
                return i;
            }
        }
        return 0;
    }

    /**
     * @dev bubbleUp: index 위치에서 부모와 비교해가며 올라가는 과정
     */
    function bubbleUp(Heap storage self, uint256 index) private {
        while (index > 1) {
            uint256 parentIndex = index / 2;
            if (self.data[parentIndex].price < self.data[index].price) {
                // swap
                Bid memory temp = self.data[parentIndex];
                self.data[parentIndex] = self.data[index];
                self.data[index] = temp;

                index = parentIndex;
            } else {
                break;
            }
        }
    }

    /**
     * @dev bubbleDown: index 위치에서 자식들과 비교해가며 내려가는 과정
     */
    function bubbleDown(Heap storage self, uint256 index) private {
        uint256 length = self.data.length;
        while (true) {
            uint256 leftChild = index * 2;
            uint256 rightChild = index * 2 + 1;
            uint256 largest = index;

            if (leftChild < length && self.data[leftChild].price > self.data[largest].price) {
                largest = leftChild;
            }
            if (rightChild < length && self.data[rightChild].price > self.data[largest].price) {
                largest = rightChild;
            }

            if (largest == index) {
                break;
            }

            // swap
            Bid memory temp = self.data[index];
            self.data[index] = self.data[largest];
            self.data[largest] = temp;

            index = largest;
        }
    }
}
