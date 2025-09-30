ifneq (,$(wildcard .env))
include .env
export
endif

deploy-permit2-local:
	forge script lib/permit2/script/DeployPermit2.s.sol --rpc-url $(LOCAL_RPC) --private-key $(DEPLOYER_KEY) --broadcast &&

deploy-executor-local:
	 forge script script/DeployExecutorMock.s.sol --rpc-url $(LOCAL_RPC) --broadcast

deploy-script-with-key:
	forge script script/DeployContract.s.sol --rpc-url $(RPC_URL) --broadcast --private-key $(KEY) -vvvv

deploy-script-with-env:
	forge script script/DeployContract.s.sol --rpc-url $(RPC_URL) --broadcast -vvvv