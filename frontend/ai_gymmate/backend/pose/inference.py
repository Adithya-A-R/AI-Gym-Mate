import torch
import cv2
import numpy as np
from pose.model import PoseNet

device = "cpu"

model = PoseNet()
model.load_state_dict(torch.load("models/posenet_demo.pth", map_location=device))
model.eval()

def preprocess(frame):
    img = cv2.resize(frame, (256, 256))
    img = img / 255.0
    img = img.transpose(2, 0, 1)
    img = torch.tensor(img, dtype=torch.float32).unsqueeze(0)
    return img

def predict_keypoints(frame):
    with torch.no_grad():
        inp = preprocess(frame)
        preds = model(inp).numpy().reshape(-1, 2)
        return preds
