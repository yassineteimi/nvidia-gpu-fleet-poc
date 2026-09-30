"""The model: an 8 layer MLP on synthetic data, in bf16 autocast so the L4's
tensor cores do the work. No dataset, so nothing is downloaded on a billed
node. Sized so a step takes a noticeable fraction of a second on an L4 and a
checkpoint (weights plus SGD momentum) is a few hundred MB.
"""

import io

import torch


class TorchBackend:
    def __init__(self, width=2048, depth=8, batch=65536, seed=0, device="cuda"):
        torch.manual_seed(seed)
        self.device = device
        layers = []
        for _ in range(depth):
            layers += [torch.nn.Linear(width, width), torch.nn.GELU()]
        self.model = torch.nn.Sequential(*layers).to(device)
        self.opt = torch.optim.SGD(self.model.parameters(), lr=1e-3, momentum=0.9)
        self.x = torch.randn(batch, width, device=device)
        self.y = torch.randn(batch, width, device=device)

    def step(self):
        self.opt.zero_grad(set_to_none=True)
        with torch.autocast(device_type="cuda", dtype=torch.bfloat16, enabled=self.device == "cuda"):
            loss = torch.nn.functional.mse_loss(self.model(self.x), self.y)
        loss.backward()
        self.opt.step()
        if self.device == "cuda":
            torch.cuda.synchronize()  # so the logged step time is the GPU's, not the launch queue's

    def save(self):
        buf = io.BytesIO()
        torch.save({"model": self.model.state_dict(), "opt": self.opt.state_dict()}, buf)
        return buf.getvalue()

    def load(self, data):
        state = torch.load(io.BytesIO(data), map_location=self.device)
        self.model.load_state_dict(state["model"])
        self.opt.load_state_dict(state["opt"])
